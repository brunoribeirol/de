# Exercício 02 (Aula 08) — do zero em Terraform

Exercício do Ciclo 2. O aluno provisiona, **100% em Terraform e com state local**,
um Data Lake mínimo (bucket, catálogo com schema declarado, ≥3 partições e workgroup
Athena com teto medido) e justifica cinco decisões. É o **primeiro incremento da
Parte 1 do projeto** (AV1, Aula 16).

## Conteúdo do pacote

```
aula-08-iac-do-zero/
├── enunciado.html               # enunciado do aluno (abre offline)
├── rubrica.md                   # critérios, pesos e o que não conta
├── aula-08.pptx                 # deck do professor (com notas)     [só no pacote do professor]
├── aluno-slides-aula-08.pptx    # deck da turma (sem notas)
├── terraform/                   # ANDAIME que o aluno recebe (não é solução)
│   ├── versions.tf              # pronto (state local, sem backend)
│   ├── providers.tf             # pronto (região + default_tags)
│   ├── variables.tf             # parcial (teto e dias sem default)
│   ├── main.tf                  # esqueleto com # DECISAO 01/02/03
│   ├── outputs.tf               # CONTRATO — o verifica.sh lê estes nomes
│   └── terraform.tfvars.example
├── dados/
│   └── gerar-corridas.py        # gera ~3,4 MB/dia por partição
├── verificacao/
│   └── verifica.sh              # PASSA/FALHA por critério
└── gabarito/                    # SOLUÇÃO — não distribuir antes da entrega [só no pacote do professor]
    ├── DECISOES.md
    ├── terraform.tfvars
    └── README.md
```

## Fluxo do aluno (resumido — o passo a passo está no enunciado.html)

```bash
export AWS_REGION=us-east-1
cd terraform && cp terraform.tfvars.example terraform.tfvars   # preencha sufixo
python3 ../dados/gerar-corridas.py --dias 8                     # gera os dados
# decida no main.tf: valor, tempo, serde; no tfvars: dias_particao e teto_bytes
terraform init && terraform apply
aws s3 cp ../dados/saida/ "s3://$(terraform output -raw bucket_name)/raw/corridas/" --recursive
cd ../verificacao && ./verifica.sh
# escreva DECISOES.md, depois:
cd ../terraform && terraform destroy
cd ../verificacao && ./verifica.sh --pos-destroy
```

## Números

- Recursos Terraform: **7 fixos** (2 buckets + 2 bloqueios + database + tabela + workgroup)
  **+ N partições** (`for_each` sobre `dias_particao`). Com 3 partições, o `apply` cria 10.
- Dados: **~3,4 MB por dia** de partição (gerador determinístico por dia).
- Teto: o aluno **mede e escolhe** (piso 10.485.760; topo útil 117.455.962).
- Custo por aluno: **< US$ 1,00**. State **local**, de propósito.

## Regras de entrega

- **Nunca entregar ao aluno:** `gabarito/`, `terraform.tfstate`, credenciais.
- O `verifica.sh` roda na conta do aluno e vale como aceite; a **nota cai no projeto** (AV1).
- `destroy` limpo é critério: bucket órfão reprova o item.
