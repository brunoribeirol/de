# Nota técnica — sintaxe do scaffold incompatível com Terraform 1.16.0

**Não é uma das 5 decisões avaliadas (critério 6).** É uma nota de ambiente,
para levar ao professor se perguntado por que o `main.tf` entregue está
formatado diferente do scaffold original.

## Sintoma

`terraform init` falhava com:

```
Error: Invalid single-argument block definition
  on main.tf line 75, in resource "aws_glue_catalog_table" "corridas":
  75:     columns { name = "corrida_id"    type = "string" }
A single-line block definition must end with a closing brace immediately
after its single argument definition.
```

## Causa raiz

O `main.tf` do scaffold, como distribuído, escreve cada bloco `columns` com
**dois atributos na mesma linha**:

```hcl
columns { name = "corrida_id"    type = "string" }
```

A gramática HCL atual só permite **um** atributo em um bloco de linha única
("single-line block sugar"); um segundo atributo na mesma linha, sem quebra,
é erro de sintaxe. Isso afeta **todas** as 18 ocorrências de `columns { ... }`
no arquivo (9 na tabela, 9 na partição) — não é específico de nenhuma decisão.

`versions.tf` só trava `required_version = ">= 1.5"`, sem teto superior — ou
seja, nada impede uma instalação local de Terraform mais nova (aqui,
`v1.16.0`) de encontrar essa incompatibilidade, mesmo que o scaffold tenha
sido validado pelo professor numa versão mais antiga (~1.5–1.9), onde essa
sintaxe provavelmente ainda era aceita de forma mais permissiva.

## Correção aplicada

Reformatação mecânica de todos os blocos `columns` para multi-linha,
**sem alterar nenhum nome de coluna, tipo ou valor de decisão**:

```hcl
# antes (nao parseia no Terraform 1.16.0)
columns { name = "corrida_id"    type = "string" }

# depois
columns {
  name = "corrida_id"
  type = "string"
}
```

Confirmado com `terraform init` (passou da fase de parse; falhou depois só
por falta de rede da sandbox de desenvolvimento usada para o teste — não
tem relação com esta correção).

## O que perguntar/avisar ao professor

- A versão de Terraform instalada localmente (`terraform version`) importa
  para quem for rodar este scaffold — vale registrar a versão testada no
  README oficial ou travar um teto em `required_version`.
- Nenhuma decisão de engenharia (01–05) foi afetada; a mudança é puramente
  de formatação/sintaxe.
