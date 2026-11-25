# DECISOES.md — Exercício 06 · grupo: grupo07

Uma frase por decisão, com o número ou a recusa que medimos. Tudo foi perguntado **como cada
perfil** (`./como.sh`, que assume o papel do perfil), na conta da turma, em 2026-11-25
(hoje = `2026-11-25`, desde = `2026-11-19`;
[`docs/evidence/profiles.txt`](docs/evidence/profiles.txt),
[`probe-new-refined-table.txt`](docs/evidence/probe-new-refined-table.txt),
[`verification-before-destroy.txt`](docs/evidence/verification-before-destroy.txt)).

| # | Variável | Escolha | O que mostra (AWS, como o perfil) |
| --- | --- | --- | --- |
| 01 | `escopo_prefeitura` | `tabela` | madrugada de 7 dias = **11.137**; tabela nova na refined = **`TABLE_NOT_FOUND`** para a Prefeitura |
| 02 | `colunas_ocultas_analista` | `motorista_id`, `passageiro_id` | `count(bairro)` = **518.400**; `SELECT passageiro_id` e `SELECT motorista_id` = **recusados**; `SELECT *` devolve 9 das 11 colunas |
| 03 | `contrato_refined` | descrição, dono, atualização, 3 comentários | critério 4 PASSA: descrição de **241** caracteres, dono e comentário em toda coluna |

## DECISÃO 01 — o alcance da Prefeitura na refined (`escopo_prefeitura`)
Escolhemos **`tabela`**: a Prefeitura tem `SELECT` e `DESCRIBE` só na `madrugada_bairro`, e não
no database refined. Com essa escolha, se alguém criar amanhã uma tabela nova na refined, a
Prefeitura **não a enxerga até alguém conceder**. Medimos isso: depois do `apply`, criamos na
refined a `sonda_tabela_nova`, sobre os mesmos arquivos da `madrugada_bairro`. Como a Prefeitura,
a consulta deu **`TABLE_NOT_FOUND`**: para ela, a tabela nem existe. Como a analista, que tem o
database inteiro (curinga), a mesma consulta deu **11.137** no mesmo minuto. A madrugada dos
últimos 7 dias, lida como a Prefeitura, deu **11.137 corridas**, e a refined inteira, **660
linhas** (22 bairros × 30 dias). É uma escolha diferente da do Lab 07, que usou o banco. O
jurídico só aceita o painel se a Prefeitura não vir **nenhum id**, e a refined é onde o time vai
pôr a próxima tabela. Com o banco, uma tabela nova com id, feita para uso interno, iria para a
Prefeitura no mesmo instante, sem ninguém decidir nada. A sonda mostra isso acontecendo com a
analista. O que aceitamos perder: cada tabela nova para o painel exige uma concessão explícita
(mais um `aws_lakeformation_permissions` e um PR), e a Prefeitura só a vê depois disso.

## DECISÃO 02 — as colunas que a analista não vê (`colunas_ocultas_analista`)
Escondemos **`passageiro_id` e `motorista_id`**. A analista continua lendo **9 das 11 colunas**:
`SELECT *` como ela devolveu `corrida_id`, `bairro`, `inicio`, `fim`, `distancia_km`,
`duracao_min`, `valor`, `faixa_hora` e `chegada`, mais a partição `dt`. `SELECT passageiro_id`
como ela deu **recusado** (`COLUMN_NOT_FOUND`): o Lake Formation corta a coluna antes de o
Athena planejar a consulta, e para ela a coluna não existe. `SELECT motorista_id` deu o mesmo, e
`count(bairro)` deu **518.400**. Deixamos visível `corrida_id` porque ela precisa dele para achar
a corrida reclamada: a reclamação chega com o id da corrida, e `count(DISTINCT corrida_id)` =
**518.400** mostra que ela ainda isola cada uma. Escondemos também o motorista porque o
enunciado diz que ela "não investiga pessoa", e o motorista é pessoa tanto quanto o passageiro.
O que aceitamos perder: ela não consegue ver que um mesmo motorista concentra reclamações. Se
isso for preciso, é outro papel, com outra concessão.

## DECISÃO 03 — o contrato da refined (`contrato_refined`)
A descrição diz **o que a tabela responde** (corridas e receita da madrugada, com início entre
00h e 05h59, por bairro e dia, para o painel da Secretaria de Mobilidade) e **o que ela não tem**
(nenhum id: nem de corrida, nem de motorista, nem de passageiro). Ela tem **241 caracteres**, e o
mínimo é 40. Um consumidor que só ler o catálogo sabe o grão (uma linha por bairro e dia), o que
conta como madrugada (`faixa_hora` de 0 a 5) e que `receita` é a soma de `valor` em reais com 2
casas. Sabe também que a tabela não tem nenhum id, e que para investigar uma corrida a fonte é a
trusted. O dono é **Engenharia de Dados (grupo 07)**. A tabela muda **diariamente**, pelo job
refined, depois do job trusted. Cada execução reescreve só os dias que calcula, e `dt` é o dia
da corrida, não o dia em que o arquivo chegou, como na raw. O `verifica.sh` leu tudo isso no
catálogo (critério 4: **PASSA**, descrição de 241 caracteres, dono e comentário em toda coluna;
[catálogo](docs/evidence/catalog-contract.json)). O número que a Prefeitura leu (660 linhas = 22
bairros × 30 dias) confere com o grão que o contrato declara.

## Achados da execução

**1. O pacote não deixava nenhum perfil consultar, e o critério 2 passava pelo motivo errado.**
A primeira execução deu **35/70**: toda consulta como perfil, inclusive as permitidas, falhou com
`Unable to verify/create output bucket eda-a29-lake-grupo07` (`INSUFFICIENT_PERMISSIONS`). O
critério 2 passou só porque tudo era recusado, e o 1 e o 3 caíram
([saída](docs/evidence/verification-attempt-1-output-bucket-denied.txt)). Como a Prefeitura, um
`get-bucket-location` deu `AccessDenied ... because no identity-based policy allows the
s3:GetBucketLocation action`
([antes](docs/evidence/diagnose-output-bucket-before-fix.txt)). A causa estava na policy
`consumo`, uma das partes que vêm prontas: `s3:GetBucketLocation` estava na mesma instrução que
`s3:ListBucket`, sob a condição `s3:prefix`. Só o `ListBucket` leva essa chave; no
`GetBucketLocation` ela não existe, a condição dá falso, e o Athena não consegue checar o bucket
de resultados. A correção põe o `GetBucketLocation` numa instrução própria, sem condição. Ele só
revela a região do bucket. O `ListBucket` manteve a condição. Aplicamos só essa policy
(`-target`; o plano exigido e obtido foi `0 to add, 1 to change, 0 to destroy`,
[plano](docs/evidence/plan-fix-output-bucket.txt)). Depois dela, o `get-bucket-location` como a
Prefeitura passou, e listar `refined/` continuou **recusado**
([depois](docs/evidence/diagnose-output-bucket-after-fix.txt)). O `verifica.sh` deu **70/70**.

**2. A conta é compartilhada, e o Lake Formation tem uma configuração só para a conta inteira.**
Antes do `apply`, a conta tinha **3 administradores** do Lake Formation (`eda-grupo09`,
`gportela` e `eda-grupo04`) e dava acesso automático (`IAMAllowedPrincipals`) a databases e
tabelas novos ([antes](docs/evidence/lf-settings-before.txt)). O
`aws_lakeformation_data_lake_settings` do pacote **substitui** essa lista por quem roda o
Terraform. Destruí-lo **esvazia** a lista e as permissões padrão da conta inteira, inclusive de
quem estiver no meio do próprio lab. Por isso guardamos as configurações antes do `apply`, e no
teardown tiramos esse recurso do estado (`terraform state rm`) antes do `destroy`. Assim o
`destroy` remove os outros 31 recursos e não mexe na configuração da conta. Depois, devolvemos os
administradores de antes, mais quem tivesse entrado no meio tempo, e as permissões padrão.
Resultado no [teardown](#teardown).

**3. Custo.** Foram duas execuções de job, com 2 DPU cada: trusted de cerca de 12:19:50 a
12:22:03, e refined até 12:23:35
([jobs](docs/evidence/jobs-run-1.txt)). Isso dá ≈ 0,12 DPU-hora × US$ 0,44 ≈ **US$ 0,05**, mais
centavos de Athena e S3. A consulta mais cara foi a `count(DISTINCT corrida_id)` da analista
(2,56 MB lidos). A Prefeitura leu o painel com **998 bytes**. É uma estimativa pelo relógio do
`rodar-jobs.sh`, não pela fatura.

## Teardown

**Destroy limpo, checado três vezes, e a conta devolvida como estava.** A configuração da conta
saiu do estado ([`state rm`](docs/evidence/state-rm-lf-settings.txt)), e o `terraform destroy`
removeu **30 recursos** (`Destroy complete! Resources: 30 destroyed`). O `state list` ficou
vazio ([estado](docs/evidence/state-after-destroy.txt)). O `verifica.sh --pos-destroy` deu
**PASSA [5]** ([saída](docs/evidence/post-destroy-verification.txt)). Esse script descarta o erro
de cada chamada, e uma falha de rede pareceria "ausente". Por isso uma checagem independente
imprimiu a resposta de cada serviço: `404 Not Found` no bucket, `EntityNotFoundException` nos 3
databases e nos 2 jobs, `INVALID_INPUT` no workgroup, `NoSuchEntity` nos 4 papéis, e nenhum
registro do bucket no Lake Formation ([checagem](docs/evidence/manual-cleanup-check.txt)).

Eram 32 recursos, saiu um do estado, e o esperado eram 31 destruídos, não 30. A diferença é a
`analista_refined`, a concessão da analista no database refined inteiro (curinga). Ela existia
às 12:36, porque a analista leu 11.137 da refined, mas sumiu do estado no *refresh* do `destroy`:
o provider não a encontrou na leitura e não a listou para destruir. Uma busca por qualquer
permissão do Lake Formation com `eda-a29-grupo07` no principal ou `eda_a29_grupo07` no recurso
voltou **vazia (`[]`)** depois do destroy
([permissões](docs/evidence/lf-permissions-after-destroy.txt)). Nada ficou para trás: apagar o
database levou junto as permissões sobre ele.

As configurações do Lake Formation voltaram às de antes: os **3 administradores**
(`eda-grupo04`, `eda-grupo09`, `gportela`) e `IAMAllowedPrincipals` como padrão para databases
e tabelas novos ([restauração](docs/evidence/lf-settings-restored.txt)). Se o `destroy` tivesse
apagado esse recurso, a conta teria ficado sem nenhum administrador do Lake Formation.
