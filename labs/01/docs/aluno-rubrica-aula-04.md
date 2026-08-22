# Rubrica — Exercício 01: o schema é seu

Pública desde a Aula 03, slide 14. **Não muda até a entrega.** É o que o
`verifica.sh` imprime, critério a critério.

| # | Critério | Como é verificado | Peso |
| --- | --- | --- | --- |
| 0 | **Sem Crawler.** Não existe `AWS::Glue::Crawler`; existe `AWS::Glue::Table` | `verifica.sh` | **elimina** |
| 1 | Os cinco outputs de contrato existem e estão preenchidos | `verifica.sh` · CloudFormation | 10% |
| 2 | `AWS::Glue::Table`: schema declarado (≥ 8 colunas) e chave de partição `dt` | `verifica.sh` · Glue API | 25% |
| 3 | `AWS::Glue::Partition` apontando para a chave certa (≥ 3, uma delas a de hoje) | `verifica.sh` · Glue API | 15% |
| 4 | O teto mata a consulta larga e deixa passar a estreita | `verifica.sh` · Athena | 15% |
| 5 | `destroy` limpo: nenhum recurso órfão | `verifica.sh --pos-destroy` | 15% |
| 6 | `DECISOES.md`: uma justificativa por decisão | leitura | 20% |

> **O critério 0 não tem peso porque não é nota: é o requisito.** Template com
> Crawler não é uma entrega pior — é outra entrega, a da Aula 03, e ela já foi
> feita pelo professor.

**Os cinco outputs de contrato:** `BucketName` · `DatabaseName` · `TableName` ·
`WorkGroupName` · `TetoBytes`. Vêm prontos no esqueleto e **não se mexe** — o
`verifica.sh` lê estes nomes. A interface é contrato. As URLs de console são
obrigatórias pela convenção e não entram no critério 1.

## O que não conta na nota

Elegância do YAML, número de recursos, `Mappings` ou `Conditions` que ninguém
pediu, recurso extra não solicitado — **e ter chegado à mesma resposta do
gabarito**.

> **Uma decisão diferente da do gabarito, bem justificada, vale 10. Uma decisão
> igual à do gabarito, sem justificativa, não passa de 8.**

**Não passa:** "Usei `double` porque é número."

**Passa:** "Usei `double`: o SerDe converte sozinho e o Athena agrega direto.
Aceito que 1,5% dos eventos com vírgula decimal virem `null` — prefiro perder a
linha a perder a coluna inteira para `string`, porque `string` transfere um `cast`
para toda consulta que alguém escrever daqui em diante, e alguém vai esquecer."

## As cinco decisões (critério 6)

| # | Onde | A escolha | O que a frase precisa dizer |
| --- | --- | --- | --- |
| 01 | `Columns` · `valor` | `double`, `string` ou `decimal(10,2)` | o que você aceita perder com os 1,5% que mandam `"17,82"` |
| 02 | `Columns` · colunas de tempo | `timestamp` ou `string` | o que o `SELECT` devolveu **quando você testou** — não o que você supôs |
| 03 | `SerdeInfo` | `ignore.malformed.json` `true`/`false` | você prefere barulho ou silêncio, e quem paga o que você escolheu |
| 04 | `AWS::Glue::Partition` | quantas das 30 | o que acontece com as outras, e o que acontece **no dia 31** |
| 05 | `TetoBytesPorConsulta` | o número | de que medição ele saiu, e por que não é o piso nem o teto do intervalo |

**Uma frase por decisão. Não repita o enunciado: diga o que você aceitou perder.**

## O que mais reprova

1. `destroy` deixando **bucket órfão** — derruba o critério 5 inteiro (15%).
2. `Location` de partição que não bate com a chave real: o Athena devolve **zero
   linha sem erro nenhum**, o critério 3 cai e o 4 cai junto.
3. Teto abaixo de **10.485.760** — o Athena recusa e a stack não sobe.
4. Teto acima de **117.655.605** — o freio nunca toca e o critério 4 cai.

## Entrega

PR até o fim da aula, com `infra/template.yaml`, `infra/parameters.json`,
`DECISOES.md` e **a saída do `verifica.sh` colada**. Rode o script antes de
entregar: **a nota não é surpresa.** Trabalho fora do prazo entra com nota
inicial 8,0.

O exercício não tem nota própria: ele é o primeiro incremento da Parte 1 do
projeto, cobrado na AV1, na Aula 16.
