# DECISOES.md — Exercício 04 (Aula 21)

Layout do grupo: `chaves_particao = ["dt"]`, `arquivos_por_pasta = 1`, meta de
**524.288 bytes**, teto de **10.485.760 bytes**, partições por **partition
projection**. Todo número abaixo foi medido na conta do grupo em 21/10/2026
(`us-east-1`); a saída bruta de cada comando está em [`docs/evidence/`](docs/evidence/).

**DECISÃO 01 — chave de partição.** Escolhi `["dt"]` porque a pergunta da
madrugada filtra por data e só *agrupa* por bairro; com esta chave, a semana abre
**7 arquivos** dos 30 da trusted, enquanto `["dt", "bairro"]`
abriria 7 × 22 = **154** arquivos para ler exatamente as mesmas linhas. Aceito que
uma consulta filtrada por um único bairro leia as colunas de todos os bairros do
dia, em vez de só a pasta dele.

**DECISÃO 02 — arquivos por pasta.** Escolhi **1**; cada arquivo ficou com
~**605 KB**, e a pergunta lê **14.546 bytes de rodapés** (7 rodapés
de 2.078 bytes, 4,1% do que ela varre). Com 4 por pasta seriam 28 rodapés
(~58 mil bytes, 4× o de hoje) e 4× mais pedidos ao S3 para o mesmo dado, sem
ganho nenhum de paralelismo num dia que cabe inteiro em ~605 KB.

**DECISÃO 03 — a meta de custo.** Declarei **524.288 bytes (512 KiB)** antes de
medir. Ela saiu do Lab 05, que leu ≈ 0,4 MB nesta mesma pergunta com o mesmo dado
(seed 42) e o mesmo layout (dt, 1 arquivo por dia), mais ~25% de folga para a
variação de bytes entre versões do Spark — metade do limite de 1 MiB. O Athena leu
**355.803 bytes** (67,9% da meta), com as **11.137** corridas.

**DECISÃO 04 — o teto do workgroup.** Declarei **10.485.760 bytes (10 MiB)**, o
mínimo que o Athena aceita, com `enforce`: deixa passar a pergunta (355.803 bytes) e
até a leitura de todas as colunas de uma semana (**4.134.853 bytes**), e barra a
de todas as colunas dos 30 dias (**CANCELLED**, `Bytes scanned limit was
exceeded`; a trusted inteira tem 18.143.089 bytes). O preço tem duas partes: a
consulta barrada ainda é cobrada pelos **10.485.760 bytes** que leu antes de
parar, e qualquer consulta acima de ~58% da trusted — um full scan largo do
histórico, uma auditoria de `corrida_id` — precisa de outro workgroup, uma fatia
que encolhe a cada dia que a trusted cresce (~605 KB por dia).

**DECISÃO 05 — o registro das partições.** Escolhi **partition projection**
(`dt` do tipo `date`, faixa `2026-01-01,NOW`), e não MSCK REPAIR: o catálogo tem
**0 partições** registradas e a contagem fecha **518.400 corridas em
30 dias** mesmo assim. Aceito que só o Athena enxergue as partições — Spark, EMR e
Redshift Spectrum leem os metadados do catálogo, então a refined da Parte 2 vai
ler a trusted pelo caminho no S3, como o job já faz com a raw. No dia 31 a pasta
nova aparece sozinha quando o `NOW` chega nela, sem comando nenhum. O início é
fixo de propósito: o Athena calcula o `NOW` em UTC e o gerador grava a data local
(UTC−3), então uma janela `NOW-29DAYS` perderia o primeiro dia sempre que a
consulta rodasse depois das 21h, e a contagem cairia para 501.120 sem erro.

## Achados da execução

**A rede de quem rodou falhou ou travou quatro vezes, e nenhuma falha foi do código.** O
padrão foi sempre o mesmo: uma chamada à AWS que leva ~1 s passou a levar minutos
(o SDK repetindo a chamada) ou desistiu com erro de DNS ou de conexão.

| # | Etapa | Sintoma | Recuperação | Saída |
| --- | --- | --- | --- | --- |
| 1 | 1º `apply` | aos ~22 s, `lookup eda-tfstate-grupo07.s3.us-east-1.amazonaws.com: no such host` na operação do backend sobre o estado; o Terraform parou de agendar recursos: 4 de 11 criados (database em 3 min 43 s), os 7 dependentes do bucket nem começaram | um `plan` novo, não um `destroy` nem um `apply` cego: deu **`7 to add, 0 to change, 0 to destroy`** — o estado remoto tinha guardado os 4, sem import nem `force-unlock`; o `lab04.tfplan` antigo deixou de valer porque o estado mudou depois dele | [`apply-attempt-1-dns-failure.txt`](docs/evidence/apply-attempt-1-dns-failure.txt), [`plan-after-failed-apply.txt`](docs/evidence/plan-after-failed-apply.txt) |
| 2 | 2º `apply` | completou os 7, mas o workgroup levou **3 min 47 s** e a policy do IAM **5 min 28 s** | nenhuma: o provider AWS repete cada chamada até 25 vezes e aguentou | [`apply.txt`](docs/evidence/apply.txt) |
| 3 | carga da raw | `Could not connect to the endpoint URL` já no primeiro pedido ao S3; nada subiu (o AWS CLI v2 desiste após 3 tentativas) | troca de rede e `AWS_MAX_ATTEMPTS=10` | [`load-raw-attempt-1-network-failure.txt`](docs/evidence/load-raw-attempt-1-network-failure.txt) |
| 4 | carga da raw, 2ª tentativa | na outra rede, **0 de 30 objetos** no S3 depois de ~9 min enviando os 112 MB; interrompida | enviar a raw compactada: `gzip -n -9` leva os 30 arquivos de **117.655.606 para 13.945.588 bytes** (−88%), com o mesmo conteúdo (descompactar devolve o JSON byte a byte); o Spark e o Athena leem `.json.gz` sozinhos, pela extensão. Subiu: **30 objetos, 13.945.588 bytes**, e o job leu as 518.400 linhas da raw compactada. O `aws s3 rm` antes do sync apagou 1 `.json` que a tentativa interrompida tinha deixado e que contaria aquele dia em dobro | [`load-raw.txt`](docs/evidence/load-raw.txt) |

**O `verifica.sh --pos-destroy` do curso passa sem checar nada no macOS.** A
função `tfvar` extrai o sufixo com `sed -E 's/^[^=]*=\s*"?…'`; o `sed` BSD do
macOS não reconhece `\s` e o lê como a letra `s`. Com a linha no formato padrão
(`sufixo = "grupo07"`, com espaço depois do `=`), o sufixo sai vazio, e o
critério 6 procura `eda-a21-lake-` em vez de `eda-a21-lake-grupo07`. O resultado
é um **PASSA vazio**: `nenhum recurso eda-a21-*- sobrou`
([saída](docs/evidence/post-destroy-verification-empty-suffix.txt)). Com
`[[:space:]]`, ou com a linha sem espaço (`sufixo="grupo07"`), sai `grupo07`;
no GNU sed (Linux) o bug não aparece. O script do curso ficou como veio. A
verificação foi refeita apontando o `TFDIR` para um `terraform.tfvars`
temporário sem espaço, e deu **`PASSA [6] ... nenhum recurso eda-a21-*-grupo07
sobrou`** ([saída](docs/evidence/post-destroy-verification.txt)). Como uma
falha de rede também faria um recurso "parecer" ausente, uma checagem
independente imprimiu o motivo de cada ausência: os 5 vieram com a resposta do
serviço (`404 Not Found`, `EntityNotFoundException` ×2, `INVALID_INPUT`,
`NoSuchEntity`), nenhum com erro de conexão
([saída](docs/evidence/manual-cleanup-check.txt)).

O que fica: com o estado no backend remoto, um `apply` interrompido é
recuperável. O que foi criado fica registrado, e o `plan` seguinte calcula só a
diferença. Diante de qualquer falha no meio, o primeiro passo é um `plan`.

## Evidências

| Decisão | Arquivo |
| --- | --- |
| 01, 02, 04, 05 | [`measure-layout.txt`](docs/evidence/measure-layout.txt) — arquivos, rodapés, consultas largas, catálogo |
| 03 e aceite (critérios 0–5) | [`verification-before-destroy.txt`](docs/evidence/verification-before-destroy.txt) |
| destroy limpo (critério 6) | [`destroy.txt`](docs/evidence/destroy.txt), [`post-destroy-verification.txt`](docs/evidence/post-destroy-verification.txt), [`manual-cleanup-check.txt`](docs/evidence/manual-cleanup-check.txt) |
| a stack e o dado | [`plan.txt`](docs/evidence/plan.txt), [`apply.txt`](docs/evidence/apply.txt), [`load-raw.txt`](docs/evidence/load-raw.txt), [`job-run.txt`](docs/evidence/job-run.txt), [`destroy.txt`](docs/evidence/destroy.txt) |
