IF OBJECT_ID(N'dbo.conta', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.conta (
        id INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_conta PRIMARY KEY,
        nome NVARCHAR(100) NOT NULL,
        instituicao NVARCHAR(50) NOT NULL,
        tipo NVARCHAR(30) NOT NULL,
        saldo_inicial DECIMAL(18,2) NOT NULL,
        CONSTRAINT CK_conta_saldo_inicial CHECK (saldo_inicial BETWEEN -9999999999999999 AND 9999999999999999)
    );
    CREATE INDEX IX_conta_nome ON dbo.conta(nome);
END;
GO

IF OBJECT_ID(N'dbo.transacao', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.transacao (
        id INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_transacao PRIMARY KEY,
        descricao NVARCHAR(150) NOT NULL,
        valor DECIMAL(18,2) NOT NULL,
        tipo NVARCHAR(10) NOT NULL,
        data DATE NOT NULL,
        conta_id INT NOT NULL,
        CONSTRAINT CK_transacao_valor CHECK (valor > 0),
        CONSTRAINT CK_transacao_tipo CHECK (tipo IN ('Receita', 'Despesa')),
        CONSTRAINT FK_transacao_conta FOREIGN KEY (conta_id) REFERENCES dbo.conta(id)
    );
    CREATE INDEX IX_transacao_conta_data ON dbo.transacao(conta_id, data);
END;
GO

IF NOT EXISTS (SELECT 1 FROM dbo.conta WHERE nome = N'Conta principal')
    INSERT INTO dbo.conta (nome, instituicao, tipo, saldo_inicial)
    VALUES (N'Conta principal', N'DimDim Bank', N'Conta corrente', 2500.00);
GO

DECLARE @descricao_inicial NVARCHAR(150) = N'Primeiro sal' + NCHAR(225) + N'rio';

UPDATE dbo.transacao
SET descricao = @descricao_inicial
WHERE descricao LIKE N'Primeiro sal%rio'
  AND descricao <> @descricao_inicial
  AND valor = 3500.00;

IF NOT EXISTS (SELECT 1 FROM dbo.transacao WHERE descricao = @descricao_inicial)
BEGIN
    INSERT INTO dbo.transacao (descricao, valor, tipo, data, conta_id)
    SELECT @descricao_inicial, 3500.00, N'Receita', CAST(GETDATE() AS DATE), id
    FROM dbo.conta WHERE nome = N'Conta principal';
END;
GO
