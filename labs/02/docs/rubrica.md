# Rubrica — Exercício 02 (Aula 08)

A mesma tabela do `enunciado.html`, e a que o `verifica.sh` imprime, critério a
critério. **Pública desde a Aula 03 — não muda.**

| # | Critério | Como é verificado | Peso |
| --- | --- | --- | --- |
| 0 | **Terraform, schema declarado, sem Crawler.** Existe `aws_glue_catalog_table`, não existe `aws_glue_crawler`; a entrega é HCL, não YAML | `verifica.sh` (grep) | **elimina** |
| 1 | Os cinco outputs de contrato existem e estão preenchidos | `verifica.sh` · `terraform output` | 10% |
| 2 | `aws_glue_catalog_table`: schema declarado (≥ 8 colunas) e chave de partição `dt` | `verifica.sh` · Glue API | 25% |
| 3 | ≥ 3 partições registradas, uma delas a de hoje, `location` batendo com a chave no S3 | `verifica.sh` · Glue API | 15% |
| 4 | **O teto mata a consulta larga e deixa passar a estreita** | `verifica.sh` · Athena | 15% |
| 5 | `destroy` limpo: **nenhum recurso órfão** | `verifica.sh --pos-destroy` + console | 15% |
| 6 | `DECISOES.md`: uma justificativa por decisão (01 a 05) | leitura | 20% |

**Critério 0 não tem peso porque não é nota: é o requisito.** Entrega com Crawler,
ou em CloudFormation, não é uma entrega pior — é outra entrega.

**Os cinco outputs de contrato** (em `outputs.tf`, **não se mexe** — o `verifica.sh`
lê estes nomes): `bucket_name` · `database_name` · `table_name` · `workgroup_name`
· `teto_bytes`.

**O que NÃO conta na nota:** elegância do HCL; número de recursos; `for_each`/
`locals` que ninguém pediu; recurso extra não solicitado; e ter chegado à mesma
resposta do gabarito.

> Uma decisão **diferente** da do gabarito, **bem justificada**, vale 10.
> Uma decisão **igual** à do gabarito, **sem justificativa**, não passa de 8.

**O que mais reprova**

1. `destroy` deixando **bucket órfão** — derruba o critério 5 inteiro (15%).
2. `location` de partição que não bate com a chave real no S3: o Athena devolve
   **zero linhas sem erro nenhum**, o critério 3 cai e o 4 cai junto.
3. Teto abaixo de **10.485.760** — o Athena recusa e a stack não sobe.
4. Teto acima do volume que você subiu — o freio nunca toca e o critério 4 cai.

**Entrega.** PR ao fim da aula, com a pasta `terraform/` completa, o
`terraform.tfvars`, o `DECISOES.md` e **a saída do `verifica.sh` colada**. Rode o
script antes de entregar: **a nota não é surpresa.** Trabalho fora do prazo entra
com nota inicial **8,0**.

> **v2 — o exercício não tem nota própria.** Ele é o **primeiro incremento da
> Parte 1 do projeto** (AV1, Aula 16). O `verifica.sh` vale como aceite; a nota
> cai no projeto. **State local:** este exercício roda com `terraform.tfstate` no
> seu laptop — é de propósito, e a dor disso é o gancho do Ciclo 3.
