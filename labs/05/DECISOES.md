# DECISOES.md — Exercício 05 · grupo: grupo07

Uma frase por decisão, com o número que medimos. Os números da AWS saem do relatório que o
job grava e das consultas no Athena, na conta do grupo, em 2026-11-04 (hoje = `2026-11-04`,
D-3 = `2026-11-01`, D-5 = `2026-10-30`; [`docs/evidence/`](docs/evidence/)). As alternativas
que não rodamos na AWS vêm de um modelo local do job
([`verification/model-choices.py`](verification/model-choices.py),
[saída](docs/evidence/model-choices.txt)), que aplica as mesmas regras do
`pipeline-corridas.py` ao mesmo cru (seed 42, atraso 3, reentrega 5). Para a combinação que
escolhemos, a AWS deu exatamente os números que o modelo previu.

| # | Variável | Escolha | O número (AWS) |
| --- | --- | --- | --- |
| 01 | `modo_escrita` | `sobrescrever` | rodar de novo: 518.400 → 518.400 linhas (em `append`: 1.036.800) |
| 02 | `chave_dedup` | `corrida_id` | 17.280 duplicatas removidas; 518.400 linhas = 518.400 corridas |
| 03 | `janela_atraso_dias` | `3` | madrugada de 7 dias = 11.137, `fora_da_janela` = 0 |
| 04 | backfill | `./rodar-job.sh DIAS=2026-11-01` | 1 pasta reescrita, a tabela fica com 518.400 linhas |

## DECISÃO 01 — modo de escrita (`modo_escrita`)
Escolhemos `sobrescrever`. O job troca só as pastas `dt=` que escreve
(`partitionOverwriteMode=dynamic`), em vez de acrescentar arquivos. Rodando o job duas
vezes, a tabela foi de **518.400 para 518.400 linhas** e a madrugada de **11.137 para
11.137**. A pasta de hoje continuou com **1 arquivo** Parquet, agora com o horário da
segunda execução (10:46:23 → 10:51:42), e a trusted continuou com 30 objetos
([1ª](docs/evidence/measure-after-run-1.txt), [2ª](docs/evidence/measure-after-run-2.txt)).
O `verifica.sh` rodou o job uma terceira vez e mediu o mesmo: 518.400 → 518.400 e 11.137 →
11.137. Em `append`, o mesmo retry levaria a tabela a 1.036.800 linhas e a madrugada a
22.274 (modelo; o Lab 06 mostrou os mesmos números na tela). O que aceitamos perder: a
tabela deixa de guardar o que a execução anterior gravou nas pastas que a nova reescreve.
Para saber o que um run fez, a fonte é o relatório dele, não a tabela.

## DECISÃO 02 — a chave da linha (`chave_dedup`)
Escolhemos `corrida_id`. Com o reenvio de 5 dias atrás, o job leu **535.680 linhas** da
raw, removeu **17.280 duplicatas**, e a tabela ficou com **518.400 linhas para 518.400
corridas distintas** ([relatório](docs/evidence/job-run-1.txt)). Sem chave e com a mesma
janela, o `sobrescrever` continua idempotente, mas a madrugada daria **12.728**, o número
errado do painel do cenário, e a tabela teria 535.680 linhas para 518.400 corridas
(modelo). O que aceitamos perder: quando a mesma corrida chega duas vezes, fica a primeira
chegada (o job ordena por `chegada`). Aqui as duas cópias são idênticas e nada se perde. Se
o produtor reenviasse uma corrida *corrigida*, a regra teria de ser "fica a última", e
essa troca é no script, não numa variável.

## DECISÃO 03 — janela de atraso (`janela_atraso_dias`)
Escolhemos **3 dias**: é o menor valor em que `fora_da_janela` é zero para este cru. No
cru, o atraso é 0 em 516.809 linhas, 1 dia nas 17.280 do reenvio e 3 dias nas 1.591 da
madrugada que chegou atrasada. A madrugada dos últimos 7 dias deu **11.137 corridas**, com
`fora_da_janela` = **0** e os 7 dias com 1.591 corridas de madrugada cada, inclusive D-3.
Cada execução diária relê **4 dias de chegada** (hoje e os 3 anteriores). Com janela 2, a
madrugada cairia para 9.546 (`fora_da_janela` = 1.591). De 4 a 7 dias, a resposta continua
11.137, mas cada execução releria até 8 dias de chegada, e o número de cada dia no painel
continuaria podendo mudar por até 7 dias (modelo). Uma ressalva sobre esse "relê": este job,
com `DIAS=todos`, lê a raw inteira (as 535.680 linhas) e regrava **30 pastas** em toda
execução (`dias_gravados_neste_run` = 30). Aqui a janela filtra; ela não encurta a leitura.
Os 4 dias são o custo de um job incremental que só lê as chegadas de que precisa. O que
aceitamos perder: uma corrida com 4 ou mais dias de atraso fica fora da carga diária. Mas
ela não some em silêncio: aparece em `fora_da_janela` no relatório, e o conserto é o
backfill (DECISÃO 04).

## DECISÃO 04 — o backfill
Se uma corrida chegar com mais atraso do que a janela, o comando que conserta é
**`./rodar-job.sh DIAS=<dia do evento>`**. Para a madrugada atrasada, foi
`./rodar-job.sh DIAS=2026-11-01` (D-3). Ele reescreve **1 pasta** (`dt=2026-11-01`, com
17.280 linhas, aceitando qualquer atraso, porque no backfill a janela não vale), e a tabela
fica com **518.400 linhas** e 11.137 na madrugada
([relatório](docs/evidence/job-run-3-backfill-d3.txt)). Não duplica por duas razões.
Primeiro, o `sobrescrever` dinâmico troca só a pasta daquele dia: a de D-3 ganhou um
arquivo novo (11:01:26), e as de D-5 e de hoje mantiveram o arquivo da segunda execução,
com o mesmo nome e o mesmo horário (10:51:42)
([medição](docs/evidence/measure-after-backfill-d3.txt)). Segundo, a chave colapsa as
chegadas repetidas da mesma corrida dentro do dia. No modelo, com uma janela curta demais
para o atraso (2 dias), o mesmo comando leva a madrugada de 9.546 para 11.137 e a tabela de
516.809 para 518.400 linhas, e rodar o backfill de novo não muda nada.

## Por que o critério 3 existe: o número certo pelo motivo errado

O modelo achou duas combinações que acertam a madrugada sem acertar a tabela. Com janela 1
ou 2 e sem chave, a madrugada dá **11.137**, mas a tabela tem 534.089 linhas para 516.809
corridas. O reenvio de D-5 soma 1.591 corridas à madrugada, e a janela curta tira as 1.591
atrasadas de D-3. Os dois erros se cancelam no número do painel. Com `sobrescrever`, essa
combinação ainda passa no critério 2 (é idempotente). Só a contagem de linhas contra
corridas distintas, o critério 3, a reprova. Conferir só o número do painel não basta.

## Achados da execução

**O primeiro `apply` caiu na rede, de novo, e nenhuma falha foi do código.**

| # | Etapa | Sintoma | Recuperação | Saída |
| --- | --- | --- | --- | --- |
| 1 | 1º `apply` | `lookup iam.amazonaws.com: no such host` ao criar o papel do job; 6 de 10 criados (bucket, database, as 2 tabelas, workgroup, script), e os 3 que dependem do papel (anexo da policy, policy do bucket, job) nem começaram. `StatusCode: 0` e `RequestID` vazio: o pedido não chegou a sair da máquina | checar a rede antes de mexer no estado: os três hosts resolveram, e `aws iam get-role` deu `NoSuchEntity`, ou seja, o papel não existia e não havia o que importar. Um `plan` novo deu **`4 to add, 0 to change, 0 to destroy`** (o `apply` só rodou depois de um `grep` exigir exatamente isso), e o 2º `apply` criou os 4. O `lab05.tfplan` antigo deixou de valer porque o estado mudou depois dele | [`apply-attempt-1-dns-failure.txt`](docs/evidence/apply-attempt-1-dns-failure.txt), [`network-check-after-failed-apply.txt`](docs/evidence/network-check-after-failed-apply.txt), [`plan-after-failed-apply.txt`](docs/evidence/plan-after-failed-apply.txt), [`apply.txt`](docs/evidence/apply.txt) |
| 2 | carga da raw | nenhum: por causa do achado 4 do Exercício 04 (a carga de 112 MB travou nesta mesma rede), a raw subiu já compactada | os mesmos passos do `carregar-raw.sh` (gerar, plantar, `rm`, `sync`), com `gzip -n -9` antes do `sync` e `AWS_MAX_ATTEMPTS=10`: **32 objetos, 14.411.679 bytes**, e o job leu as 535.680 linhas | [`load-raw.txt`](docs/evidence/load-raw.txt) |

**Os dois portões que o pacote do Lab-demo 06 deixou abertos foram fechados no Glue 4.0.**
O pacote só tinha rodado o job em Spark 3.5 local. Na AWS (Glue 4.0, Spark 3.3), o
`partitionOverwriteMode=dynamic` funcionou gravando no S3: o backfill trocou só a pasta de
D-3, e a trusted ficou com 30 objetos do começo ao fim. Se o overwrite fosse da tabela
inteira, o backfill a teria deixado com as 17.280 linhas de um dia. A partition projection
das tabelas também funcionou: o Athena viu os 7 dias sem nenhum `MSCK REPAIR`.

**Idempotente no conteúdo, não nos bytes.** Da 1ª para a 2ª execução, os arquivos medidos
e o total da trusted saíram com o mesmo tamanho (D-3: 607.433 bytes; total: 18.228.296
bytes). O backfill gravou as mesmas 17.280 linhas de D-3
em 606.302 bytes: o plano de execução é outro (filtra pelo dia do evento, não pela janela),
a ordem das linhas dentro do arquivo muda, e o Parquet comprime diferente. Por isso o
critério 2 compara contagens, não checksums. Uma verificação por hash do arquivo reprovaria
um pipeline correto.

**Custo e tempo.** Foram 4 execuções do job (1ª, 2ª, backfill e a do `verifica.sh`), cada
uma de 2 min 00 s a 2 min 32 s entre o disparo e o `SUCCEEDED`, com 2 DPU. A estimativa
pelo tempo observado é ≈ 0,29 DPU-hora × US$ 0,44 ≈ **US$ 0,13**, mais centavos de Athena
e S3, dentro do teto de US$ 1,00. É uma estimativa pelo relógio do `rodar-job.sh`, não pela
fatura.

**Destroy limpo, checado duas vezes.** `terraform destroy` removeu os 10 recursos
(`Destroy complete! Resources: 10 destroyed`), e o `state list` saiu vazio. O objeto de
estado continuou no backend do grupo (`aula25/grupo07/terraform.tfstate`, 798 bytes):
o backend não é deste exercício. O `verifica.sh --pos-destroy` deu **PASSA [5]**. O sufixo
deste verificador sai certo no macOS, porque ele usa ` *`, e não `\s`, no `sed`. Como o
script descarta o erro de cada chamada, uma falha de rede também pareceria "ausente". Por
isso uma checagem independente imprimiu a resposta do serviço para cada recurso: `404 Not
Found`, `EntityNotFoundException` ×2, `WorkGroup is not found` e `NoSuchEntity`, todas do
serviço e nenhuma de conexão ([destroy](docs/evidence/destroy.txt),
[estado](docs/evidence/state-after-destroy.txt),
[verificador](docs/evidence/post-destroy-verification.txt),
[checagem](docs/evidence/manual-cleanup-check.txt)).
