# DECISÕES

## DECISAO 01 - A fronteira do módulo

Entraram no `modules/lake/` os seis recursos que **são** o data lake: os dois
buckets (`lake` e `results`), o bloqueio de acesso público, o banco e a tabela do
Glue, e o WorkGroup do Athena. Ficaram na raiz o provider com `default_tags`, as
variáveis com validação, o bloco `backend` e os cinco outputs de contrato.

O critério foi: o módulo descreve **o que** existe, a raiz descreve **como e onde**
aquilo é criado. Provider e backend são decisões do ambiente, não do lake — um
módulo que fixa o próprio provider não pode ser reusado em outra região ou conta,
que é justamente o ponto de virar módulo. Pela mesma razão, a validação do
`sufixo` ficou na raiz: ela protege a interface com quem digita o comando, e o
módulo confia em quem o chama.

Nenhum recurso foi renomeado. `aws_s3_bucket.lake` continua `aws_s3_bucket.lake`,
só que agora sob `module.lake`. Renomear ao mover transformaria a refatoração em
recriação — o erro que a rubrica mais penaliza.

O trade-off é que o módulo, do jeito que está, não é genérico: ele recebe
`sufixo` e `teto_bytes` e nada mais, então outra stack que precisasse de um lake
com nomes diferentes teria que estender a interface. Foi uma escolha deliberada —
generalizar um módulo com um único consumidor é abstração especulativa, e este
exercício proíbe mudar qualquer coisa que altere o `plan`.

### Evidências

Zero `resource` na raiz, os seis dentro do módulo, com os nomes originais:

[a fronteira do módulo, lida do código](docs/evidence/decision-01/module-boundary.txt)

## DECISAO 02 - Como o estado foi movido

Usei `terraform state mv`, seis vezes, um comando por recurso — e não blocos
`moved {}`. A rubrica aceita os dois.

O `state mv` foi escolhido porque é **explícito e imediato**: cada comando
responde na hora (`Successfully moved 1 object(s)`), e o serial do estado avança
a cada movimento, deixando um rastro auditável. O `moved {}` é declarativo e vive
no código: ele é melhor quando a mudança precisa ser reproduzida por outras
pessoas ou em outro ambiente — num módulo publicado, por exemplo, o consumidor
não roda `state mv` por você. Aqui a refatoração é local, acontece uma vez e o
estado é único; o valor de deixar um bloco `moved {}` permanente no código seria
baixo, e ele viraria lixo a ser removido depois.

O que aprendi é que o `state mv` não fala com a AWS. Nenhuma das seis chamadas
gerou requisição de infraestrutura: elas reescrevem o endereço no arquivo de
estado. É por isso que a operação é instantânea e reversível — e é por isso que
ela é perigosa se feita pela metade, porque o estado passa a descrever uma
realidade que o código não confirma.

O trade-off: o `state mv` não fica registrado no repositório. Quem ler só o
diff do código não vê que a cirurgia de estado aconteceu — por isso a saída dos
seis comandos e o rastro de serial estão versionados como evidência.

### Evidências

O estado antes da refatoração, os seis movimentos, e o rastro de serial mostrando
o lineage preservado do serial 7 ao 13:

[estado antes da refatoração](docs/evidence/decision-02/state-list-before-refactor.txt) ·
[saída dos seis state mv](docs/evidence/decision-02/state-mv-output.txt) ·
[rastro de serial e lineage](docs/evidence/decision-02/state-mv-serial-trail.txt)

## DECISAO 03 - Workspace em vez de pasta, e por que a stack ficou no `default`

Criei o workspace `dev` e voltei para o `default`, onde a stack migrada vive.

**Por que workspace e não pasta:** os ambientes deste exercício são idênticos em
forma e diferentes só em nome — mesmo módulo, mesmas variáveis, sufixo diferente.
Workspace resolve isso sem duplicar código: um estado por workspace, um `backend`
só. Pasta por ambiente é a escolha certa quando os ambientes **divergem de
verdade** (prod tem réplica e dev não, contas diferentes, políticas diferentes),
porque aí o código duplicado deixa de ser duplicação e passa a ser diferença
legítima. Para o mesmo código com outro nome, pasta é cópia sem ganho.

**Por que a stack migrada ficou no `default`:** foi nele que o estado local
aterrissou na migração, e é ele que o `backend` endereça direto pelo `key`
(`aula12/brlla/terraform.tfstate`). O `workspace_key_prefix = "eda-a12"` só entra
para workspaces não-default, que gravam em `eda-a12/<workspace>/<key>`. Mover a
stack para o `dev` significaria um estado vazio apontando para o mesmo código: o
`apply` criaria **uma segunda cópia** dos seis recursos na AWS, com os mesmos
nomes — ou seja, falharia por conflito de nome, depois de já ter começado. É
exatamente a recriação que o exercício proíbe. Workspace novo serve para ambiente
novo, não para renomear ambiente existente.

O trade-off dos workspaces é conhecido: como o código é o mesmo, é fácil rodar
`apply` no workspace errado. A proteção aqui é operacional (conferir o `*` na
saída de `workspace list` antes de qualquer apply), não estrutural — pasta por
ambiente daria essa proteção de graça, ao custo da duplicação.

### Evidências

O `dev` existe e o `*` está no `default`:

[workspaces, com o default selecionado](docs/evidence/decision-03/workspace-list.txt)

## DECISAO 04 - O que o plan limpo prova - e o que não prova

O `plan` fechou limpo duas vezes: com o estado ainda local, logo após os seis
`state mv`, e de novo depois da migração para o S3.

**O que ele prova:** que os endereços no estado batem com os endereços no código,
e que os atributos gravados no estado batem com os declarados. Em outras palavras,
prova que a refatoração foi de código e de endereço — nenhum dos seis recursos
foi destruído e recriado. O fato de fechar limpo **antes e depois** da migração
separa as duas mudanças: a primeira passagem isola o efeito do módulo, a segunda
isola o efeito do backend.

**O que ele não prova:** que a infraestrutura na AWS está como o código descreve.
O `plan` compara código × estado, e o `refresh` que ele faz antes atualiza o
estado a partir da AWS — mas só dos recursos e atributos que o Terraform já
conhece. Um bucket criado à mão, uma policy anexada pelo console, uma tag posta
por outra pessoa: nada disso aparece. Drift fora do que está no estado é invisível
para o `plan`, e um `plan` limpo é frequentemente confundido com "o ambiente está
correto" quando significa apenas "não tenho nada a fazer com o que eu gerencio".

Também não prova que o `apply` funcionaria: `plan` não valida permissões de
escrita nem quotas.

### Evidências

Limpo com estado local e, depois, limpo com estado remoto:

[plan limpo, estado local](docs/evidence/decision-04/plan-clean-local-original-terminal.txt) ·
[plan limpo, estado no S3](docs/evidence/decision-04/plan-clean-remote-backend.txt)

## DECISAO 05 - A ordem: o que quebraria com apply antes do state mv

A ordem correta é mover o estado e só então aplicar. Medi o custo de inverter isso
antes de seguir: com o código já em módulo e o estado ainda nos endereços antigos,
o `plan` anunciou `Plan: 6 to add, 0 to change, 6 to destroy`. Não apliquei.

Se eu tivesse aplicado, o Terraform executaria exatamente aquilo: destruir os seis
recursos e criar seis novos. As consequências concretas, nesta stack:

- **Perda de dados.** O `aws_s3_bucket.lake` guarda os eventos em
  `raw/corridas/dt=.../`. O destroy de um bucket apaga os objetos junto.
- **Falha no meio do caminho.** Recriar com os **mesmos nomes** colide com o
  namespace global do S3 e com o do Glue: o destroy começa, o create esbarra em
  nome ainda em uso ou recém-liberado, e a stack termina meio derrubada — pior que
  o ponto de partida, porque agora estado e realidade divergem.
- **Recursos órfãos.** O que foi destruído sai do estado; o que falhou ao criar
  não entra. Recuperar exige `import` manual, recurso por recurso.

A lição é que `state mv` e `apply` operam em camadas diferentes — endereço e
infraestrutura — e que o Terraform não distingue "esse recurso sumiu" de "esse
recurso mudou de nome no meu mapa". Quem dá essa informação é o operador, via
`state mv` ou `moved {}`, **antes** de deixar o `apply` agir sobre a diferença.

### Evidências

O plan que anuncia a destruição — capturado e não aplicado:

[6 to add, 6 to destroy, antes do state mv](docs/evidence/decision-05/plan-before-state-move.txt)

## Achados além das cinco decisões

### O backend compartilhado não existia

O Passo 7 pressupõe um bucket de estado já de pé. Ele não existia: a conta tinha
apenas o `eda-tfstate-grupo02`, de outro grupo, e a tabela de lock `eda-tflock`.
O `init -migrate-state` falhou com `NoSuchBucket`, abortando antes de tocar em
qualquer estado ("source and destination remain unmodified").

Gravar no bucket do grupo 02 foi descartado: o estado ficaria legível por eles e
sumiria no dia da limpeza deles. Criar o bucket pelo console foi descartado por
não deixar rastro nem garantir versionamento e criptografia.

A escolha foi provisionar o backend do grupo 07 como **stack de Terraform
separada**, em [`infra/tfstate-backend/`](../../infra/tfstate-backend/), fora de
`labs/`: bucket `eda-tfstate-grupo07` com versionamento, criptografia, bloqueio
de acesso público, expiração de versões antigas, policy negando HTTP e
`prevent_destroy`. A tabela `eda-tflock` entra como `data source`, não como
`resource` — ela já existe e é da turma; declará-la como recurso seria reivindicar
posse de algo que não é meu.

A stack é separada porque o backend **sobrevive ao `destroy` do lab**, como o
próprio enunciado exige. Se o bucket morasse dentro de `labs/03/terraform/`, o
`prevent_destroy` faria o `destroy` do exercício falhar inteiro.

Como o bucket é do grupo e os recursos do lab são individuais, o `key` carrega o
sufixo pessoal (`aula12/brlla/terraform.tfstate`). Sem isso, dois colegas de grupo
no workspace `default` sobrescreveriam o estado um do outro em silêncio. A
migração confirmou que a separação funcionou: *"No existing state was found in the
newly configured s3 backend"*.

[a migração que falhou](docs/evidence/environment/init-migrate-state-failed-backend-missing.txt) ·
[a migração bem-sucedida](docs/evidence/environment/init-migrate-state-success.txt) ·
[o backend aplicado e estável](docs/evidence/environment/bootstrap-plan-no-changes.txt)

### `dynamodb_table` está deprecated no Terraform 1.16

O `init` avisa: *"The parameter `dynamodb_table` is deprecated. Use parameter
`use_lockfile` instead."* Desde o Terraform 1.11, o lock pode ser feito por um
arquivo no próprio S3, dispensando o DynamoDB. Mantive o `dynamodb_table` porque
a tabela é a infraestrutura compartilhada da disciplina e trocar o mecanismo de
lock unilateralmente deixaria minha stack sem proteção contra os colegas que
continuam usando a tabela — dois mecanismos diferentes não se bloqueiam entre si.
É uma dívida técnica consciente, não um descuido.

### Terceiro bug de verificador da disciplina

No critério 3, o `verifica.sh` imprimiu o aviso de deprecation **junto** com o
nome do workspace:

```
workspace(s) além do default: ╷ │Warning:DeprecatedParameter ... │ dev
```

Ele lê `terraform workspace list` sem separar stderr de stdout. O critério passou
por acaso, porque o `dev` aparece no fim da string; um aviso emitido depois da
lista teria o efeito contrário. Some-se isso ao bug `CANCELLED` × `FAILED` visto
nos Labs 01 e 02: os verificadores da disciplina tratam saída de terminal como
dado estruturado, sem isolar os fluxos.

### Evidências

Tabela geral do que está versionado em `docs/evidence/`:

| Pasta | Conteúdo |
| --- | --- |
| `decision-01/` | fronteira do módulo, lida do código |
| `decision-02/` | estado antes, os seis `state mv`, rastro de serial/lineage |
| `decision-03/` | workspaces, com o `default` selecionado |
| `decision-04/` | plan limpo local e plan limpo remoto |
| `decision-05/` | o plan `6 to add, 6 to destroy`, não aplicado |
| `environment/` | apply da stack plana, as duas migrações, backend do grupo |
