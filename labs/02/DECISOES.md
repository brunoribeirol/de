# DECISÕES

## DECISAO 01 - Tipo da coluna `valor`

O gerador deste exercício não produz a inconsistência de vírgula decimal do Lab 01: conferi com `grep` nas 128.000 linhas geradas (8 dias) e encontrei zero ocorrências de `valor` formatado como string/vírgula — todo valor vem como número JSON limpo, com ponto decimal.

Sem sujeira para proteger, a escolha deixa de ser sobre preservação e passa a ser sobre precisão monetária. Optamos por `decimal(10,2)` porque representa exatamente valores de dinheiro, enquanto `double` (ponto flutuante binário) pode acumular erro de arredondamento em somas de muitas linhas.

O trade-off: com `double` aceitaríamos perder exatidão em agregações; com `decimal`, não perdemos nada, já que o dado chega limpo — foi só uma questão de escolher o tipo tecnicamente correto em vez do default do esqueleto.

### Evidências

A verificação nos 128.000 registros gerados não encontrou nenhuma ocorrência de `valor` com vírgula ou entre aspas:

[grep confirma zero ocorrências de vírgula em `valor`](docs/evidence/decision-01/valor-no-comma-decimal.txt)

## DECISAO 02 - Tipo das colunas temporais

Testado via Athena: `SELECT data_corrida, try(CAST(data_corrida AS timestamp)) FROM corridas LIMIT 5` devolveu `NULL` em 5 de 5 linhas.

O gerador só escreve hora (`HH:MM:SS`), sem componente de data — e o tipo `timestamp` do Athena exige `AAAA-MM-DD HH:MM:SS`. Declarar `timestamp` faria a coluna inteira virar `NULL` silenciosamente em toda linha, o que é estritamente pior que manter `string`.

O trade-off: com `string`, não temos conversão automática de data/hora nas consultas, precisando recortar a hora com `substr()`/regex quando necessário — uma troca justa por não perder 100% dos dados da coluna.

### Evidências

O `CAST` para `timestamp` retornou `NULL` em todas as linhas testadas:

[resultado do teste de CAST para timestamp](docs/evidence/decision-02/timestamp-cast-returns-null.txt)

## DECISAO 03 - Tratamento de JSON malformado

Foi definido `true` para `ignore.malformed.json`.

O gerador deste exercício, assim como o do Lab 01, não produz JSON estruturalmente inválido — não há evidência de linha malformada nestes dados, então esta decisão é preventiva, não reativa a algo observado. Mantemos `true` para que uma única linha malformada não derrube a consulta inteira, priorizando disponibilidade.

O trade-off é que um problema de qualidade pode ficar menos visível (aparecendo como menos linhas retornadas, não como erro explícito), exigindo monitoramento de volume separado. Quem paga esse custo é quem confia no resultado sem checar a contagem esperada.

## DECISAO 04 - Partições registradas

Comecei registrando as 3 partições mínimas exigidas pelo critério, mas medir a Decisão 05 revelou um problema: com apenas 3 partições, a consulta larga varre ~10.178.476 bytes — **abaixo do piso mínimo permitido para `teto_bytes`** (10.485.760 bytes). Nenhum teto válido conseguiria bloquear essa larga nessas condições.

Registrei então uma 4ª partição (`2026-08-31`), usando dado que já estava no S3, elevando a varredura larga para um patamar onde existe uma janela válida de teto. Partições registradas: `2026-09-06` (hoje), `2026-09-03`, `2026-08-30`, `2026-08-31`.

Os outros 4 dias gerados (`2026-09-01`, `2026-09-02`, `2026-09-04`, `2026-09-05`) continuam existindo fisicamente no S3, mas são invisíveis para o Athena — validado abaixo.

O trade-off é operacional: um dado novo (por exemplo, o dia de amanhã) fica invisível até alguém registrar a partição manualmente — não há automação de `BatchCreatePartition` neste exercício.

### Evidências

A consulta para `2026-09-05` retorna zero linhas mesmo com o arquivo presente no S3, porque a partição não está registrada no Glue:

[consulta em partição não registrada retorna zero linhas](docs/evidence/decision-04/unregistered-partition-query.txt)

## DECISAO 05 - Limite de bytes por consulta

O limite foi definido a partir de medição real via Athena (AWS CLI):

- Consulta estreita (1 partição, hoje): `3.393.451` bytes
- Consulta larga (4 partições registradas): `13.571.123` bytes

O parâmetro `teto_bytes` foi definido como `12.522.547` — o total da larga menos 1 MiB (`1.048.576` bytes), mesmo critério usado no Lab 01. O valor fica acima do piso permitido (`10.485.760`), abaixo do total da larga (bloqueia) e bem acima da estreita (deixa passar).

A intenção foi posicionar o limite entre o volume de uma consulta restrita a uma partição e o volume necessário para consultar todas as partições registradas — não o piso mínimo da AWS, e sim um valor derivado do volume real dos dados.

Na validação, a consulta larga terminou com o estado `CANCELLED` e o motivo `Bytes scanned limit was exceeded` — o freio funcionou exatamente como planejado. O `verifica.sh` reporta `FALHA` no critério 4 porque sua lógica só reconhece o estado `FAILED` como bloqueio válido; `CANCELLED` com esse motivo é o mesmo bug já documentado no Lab 01, presente no verificador, não na infraestrutura.

O trade-off é limitar consultas que precisem analisar grandes volumes de uma vez, em troca de maior controle sobre custo e volume escaneado.

### Evidências

Medição da larga e da estreita, e a saída do `verifica.sh` mostrando o `CANCELLED` com o motivo real:

[medição do teto e detalhe do bug do verificador (CANCELLED vs FAILED)](docs/evidence/decision-05/scan-limit-measurement-and-verifier-cancelled.txt)
