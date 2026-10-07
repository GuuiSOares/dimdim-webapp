# DimDim · CP5 DevOps

Aplicação financeira ASP.NET Core MVC .NET 8 com dashboard e CRUD de `Conta` e `Transacao` (`Conta 1:N Transacao`). Usa SQLite em Development e Azure SQL Database PaaS, sem container, em Production.

A solução é uma aplicação web com front-end (não é API), por isso não há JSON de operações GET, POST, PUT e DELETE.

## Dados da entrega

- Grupo: `[NOME DO GRUPO]`
- Integrantes e RMs: `[NOME — RM]`
- GitHub: `[URL DO REPOSITÓRIO]`
- Vídeo: `[URL DO VÍDEO]`

## Arquitetura

![Arquitetura Azure do DimDim](docs/arquitetura.png)

O navegador acessa o App Service por HTTPS. A aplicação consulta o Azure SQL por conexão criptografada, lê a connection string do Key Vault com identidade gerenciada e envia telemetria ao Application Insights/Log Analytics.

## Stack e estrutura

- ASP.NET Core MVC, C# e .NET 8; EF Core 8; Bootstrap
- SQLite local; Azure SQL PaaS; App Service Linux F1
- Key Vault com políticas de acesso; Application Insights e Log Analytics
- Azure CLI e scripts Bash

```text
DimDim.sln
├── src/DimDim.Web/            # aplicação MVC
├── scripts/
│   ├── ddl.sql                # PK, FK, checks, índices e inserts
│   ├── config.sh              # variáveis (RM, região, assinatura e nomes)
│   ├── 01-provisionar-infra.sh
│   ├── 02-deploy-app.sh
│   ├── 03-coletar-evidencias.sh
│   └── 99-limpar-recursos.sh
└── docs/                      # diagrama de arquitetura
```

# How-to

Use **PowerShell** apenas no teste local. Use **Git Bash**, na raiz do repositório clonado, para todas as etapas Azure.

## 1. Testar localmente — PowerShell

Na raiz do repositório:

```powershell
$env:DOTNET_ROLL_FORWARD = "Major"
dotnet restore .\DimDim.sln
dotnet run --project .\src\DimDim.Web\DimDim.Web.csproj
```

Abra a URL exibida, teste dashboard, Contas e Transações e encerre com `Ctrl+C`. Resultado esperado: build sem erros e aplicação abrindo no navegador.

## 2. Entrar no Azure — Git Bash

Na raiz do repositório:

```bash
az login
az account set --subscription "Geovanne"
az account show --query '{assinatura:name,estado:state}' -o table
```

Continue somente se a assinatura ativa for **Geovanne**. Nenhum ID deve ser salvo no projeto.

## 3. Conferir variáveis

Não há nada para executar. `scripts/config.sh` já define `RM=rm562673`, região `spaincentral`, assinatura `Geovanne` e os nomes dos recursos. O IP do firewall do SQL é detectado automaticamente pelo script 01. Se um nome global estiver ocupado, altere somente `UNIQUE_SUFFIX`. Não coloque senha nesse arquivo.

## 4. Provisionar infraestrutura e DDL — Git Bash

```bash
bash scripts/01-provisionar-infra.sh
```

Digite `SIM` para confirmar a assinatura e informe um usuário administrador do SQL e uma senha forte, que não aparece na tela. Usuário e senha não ficam salvos em nenhum arquivo. O script cria Resource Group, Log Analytics, Application Insights, Key Vault com políticas de acesso, Azure SQL Server lógico/Database Basic, firewall restrito, App Service Linux F1 e Web App .NET 8. Também habilita identidade gerenciada, Key Vault Reference, `APPLICATIONINSIGHTS_CONNECTION_STRING`, HTTPS/TLS 1.2 e `/health`.

Ao final, `scripts/ddl.sql` é aplicado com `sqlcmd`, criando as tabelas relacionadas, constraints, índices e dados demonstrativos.

**Checkpoint:** o terminal deve exibir `Infraestrutura pronta.`. Confirme:

```bash
source scripts/config.sh
az resource list -g "$RESOURCE_GROUP" --query '[].{nome:name,tipo:type}' -o table
az sql db show -g "$RESOURCE_GROUP" -s "$SQL_SERVER_NAME" -n "$SQL_DATABASE_NAME" \
  --query '{banco:name,status:status,tier:currentServiceObjectiveName}' -o table
```

## 5. Publicar — Git Bash

```bash
bash scripts/02-deploy-app.sh
```

O script executa restore/publish Release, cria ZIP com `zip` ou fallback Python, publica com `az webapp deploy --type zip`, reinicia e valida o health.

**Checkpoint esperado:** `Deploy concluído. Health check HTTP 200.`

```bash
source scripts/config.sh
curl -i "https://${WEBAPP_NAME}.azurewebsites.net/health"
echo "https://${WEBAPP_NAME}.azurewebsites.net"
```

Abra a URL da aplicação. O health deve retornar HTTP `200`.

## 6. Comprovar CRUD no Azure SQL

Abra uma sessão no **Git Bash** e mantenha-a durante o ensaio:

```bash
source scripts/config.sh
SQL_ADMIN_USER="$(az sql server show -g "$RESOURCE_GROUP" -n "$SQL_SERVER_NAME" --query administratorLogin -o tsv)"
read -r -s -p "Senha SQL: " SQLCMDPASSWORD; echo
export SQLCMDPASSWORD
sqlcmd -S "tcp:${SQL_SERVER_NAME}.database.windows.net,1433" \
  -d "$SQL_DATABASE_NAME" -U "$SQL_ADMIN_USER"
```

No `sqlcmd`, finalize consultas com `GO` e saia com `QUIT`. Ao terminar, execute `unset SQLCMDPASSWORD SQL_ADMIN_USER`.

### Conta: C/R/U/D

Use `Conta vídeo`, sem transações. Reutilize esta consulta após criar, ler/detalhar e atualizar:

```sql
SELECT id, nome, instituicao, tipo, saldo_inicial
FROM dbo.conta WHERE nome = N'Conta vídeo';
GO
```

1. **Create:** crie a conta; o `SELECT` deve retornar um registro.
2. **Read:** abra lista/detalhes; confirme os mesmos dados no `SELECT`.
3. **Update:** altere instituição, tipo ou saldo; confirme os novos valores.
4. **Delete:** exclua e troque o `SELECT` por:

```sql
SELECT COUNT(*) AS quantidade FROM dbo.conta WHERE nome = N'Conta vídeo';
GO
```

Resultado esperado: `0`.

### Transação: C/R/U/D

Crie `Conta transações` e uma transação `Transação vídeo`. Reutilize:

```sql
SELECT t.id, t.descricao, t.valor, t.tipo, t.data, t.conta_id, c.nome AS conta
FROM dbo.transacao t
JOIN dbo.conta c ON c.id = t.conta_id
WHERE t.descricao IN (N'Transação vídeo', N'Transação vídeo atualizada');
GO
```

1. **Create:** cadastre a transação ligada à conta; confira registro e FK.
2. **Read:** abra lista/detalhes e o saldo da conta; repita o `SELECT`.
3. **Update:** renomeie para `Transação vídeo atualizada` e altere valor/tipo; confirme.
4. Antes do Delete, tente excluir a conta: a aplicação deve bloquear enquanto houver transação.
5. **Delete:** exclua a transação e confirme:

```sql
SELECT COUNT(*) AS quantidade
FROM dbo.transacao WHERE descricao = N'Transação vídeo atualizada';
GO
```

Resultado esperado: `0`. Isso demonstra persistência após C/R/U/D nas duas tabelas.

## 7. Coletar evidências — Git Bash

```bash
bash scripts/03-coletar-evidencias.sh
```

O script pede a senha SQL sem eco e mostra recursos, health, telemetria, métricas SQL e registros, sem imprimir segredos.

## 8. Monitorar aplicação e banco

No Portal, abra **Application Insights** e mostre:

- Live Metrics com tráfego;
- Performance/Requests;
- Application Map/Dependencies SQL;
- Failures/Exceptions;
- Logs com:

```kusto
requests | where timestamp > ago(30m)
| project Horario=timestamp, Requisicao=name, CodigoHTTP=resultCode,
          Sucesso=success, Duracao=duration
| order by Horario desc
```

```kusto
dependencies | where timestamp > ago(30m) and type has "SQL"
| project Horario=timestamp, Dependencia=name, Destino=target,
          Sucesso=success, Duracao=duration
| order by Horario desc
```

Para abrir as métricas do banco no Portal Azure:

1. Pesquise por `sqldb-dimdim` na barra superior.
2. Abra o recurso **sqldb-dimdim**, do tipo **Banco de dados SQL**. Não abra apenas o servidor `sql-dimdim-rm562673-spc`.
3. Se o menu estiver filtrado, limpe a caixa de pesquisa lateral.
4. No menu esquerdo, abra **Monitoramento > Métricas**.
5. Em **Métrica**, selecione uma por vez: **CPU percentage**, **DTU percentage**, **Data space used**, **Successful connections** e **Failed connections**.
6. Use **Adicionar métrica** para colocar mais de uma no gráfico e mostre o período das últimas 30 minutos.

Para provar os registros persistidos, mantenha o `sqlcmd` aberto e execute:

```sql
SELECT * FROM dbo.conta ORDER BY id;
SELECT * FROM dbo.transacao ORDER BY id;
GO
```

## 9. Limpar somente após a avaliação — Git Bash

```bash
unset SQLCMDPASSWORD SQL_ADMIN_USER
bash scripts/99-limpar-recursos.sh
```

Quando o script perguntar, digite exatamente:

```text
rg-dimdim-rm562673
```

Na confirmação final, digite:

```text
EXCLUIR
```

O script aguardará a exclusão do Resource Group e tentará purgar os Key Vaults para permitir um novo provisionamento com os mesmos nomes. Não o execute antes de gravar e conferir todas as evidências.

## Segurança, custos e problemas comuns

- Segredos não são versionados; a connection string fica no Key Vault e chega ao App Service por identidade gerenciada.
- Produção lê `ConnectionStrings:DefaultConnection`; HTTPS/TLS 1.2 e firewall por IP estão ativos.
- App Service F1, SQL Basic, Key Vault e observabilidade podem gerar custos; consulte Cost Management e limpe após avaliar.
- **Assinatura:** confirme acesso a `Geovanne` com `az account list -o table`.
- **Região bloqueada:** mantenha `spaincentral` ou use outra região permitida pela política da assinatura.
- **Nome ocupado:** altere `UNIQUE_SUFFIX` em `scripts/config.sh`.
- **SQL não conecta:** se trocou de rede, execute novamente o script `01` para liberar o IP atual.
- **Erro Key Vault/500:** aguarde a política de acesso propagar e reinicie o Web App.
- **Health falhou:** `az webapp log tail -g "$RESOURCE_GROUP" -n "$WEBAPP_NAME"`.
- **Sem telemetria:** gere tráfego, aguarde alguns minutos e consulte novamente.
