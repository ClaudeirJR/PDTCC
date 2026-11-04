-- =====================================================================
-- MILZERA - Modelagem Física do Banco de Dados
-- SGBD: MySQL 8.0.16 ou superior (necessário para as restrições CHECK)
-- Padrão: tabelas e colunas em minúsculas, snake_case, sem acentos
-- =====================================================================

CREATE DATABASE IF NOT EXISTS milzera
    CHARACTER SET utf8mb4
    COLLATE utf8mb4_unicode_ci;

USE milzera;

-- ---------------------------------------------------------------------
-- 1. ALUNO
-- Regra: idade mínima de 16 anos (validada pelo trigger no fim do script)
-- Regra: senha nunca é guardada em texto puro, apenas o hash
-- ---------------------------------------------------------------------
CREATE TABLE aluno (
    id_aluno          INT UNSIGNED  NOT NULL AUTO_INCREMENT,
    nome              VARCHAR(60)   NOT NULL,
    sobrenome         VARCHAR(100)  NOT NULL,
    email             VARCHAR(150)  NOT NULL,
    senha_hash        VARCHAR(255)  NOT NULL,
    telefone          VARCHAR(20)   NULL,              -- opcional
    data_nascimento   DATE          NOT NULL,
    grau_escolaridade ENUM('1_ano_medio','2_ano_medio','3_ano_medio',
                           'medio_concluido','superior') NOT NULL,
    aceite_termos_em  DATETIME      NOT NULL,
    avisos_por_email  BOOLEAN       NOT NULL DEFAULT TRUE,
    CONSTRAINT pk_aluno PRIMARY KEY (id_aluno),
    CONSTRAINT uq_aluno_email UNIQUE (email)
) ENGINE=InnoDB;

-- ---------------------------------------------------------------------
-- 2. ADMINISTRADOR (área separada dos alunos)
-- ---------------------------------------------------------------------
CREATE TABLE administrador (
    id_admin    INT UNSIGNED  NOT NULL AUTO_INCREMENT,
    nome        VARCHAR(100)  NOT NULL,
    email       VARCHAR(150)  NOT NULL,
    senha_hash  VARCHAR(255)  NOT NULL,
    CONSTRAINT pk_administrador PRIMARY KEY (id_admin),
    CONSTRAINT uq_administrador_email UNIQUE (email)
) ENGINE=InnoDB;

-- ---------------------------------------------------------------------
-- 3. TEMA
-- Tema não é apagado: o administrador "arquiva" (ativo = FALSE),
-- por isso as chaves estrangeiras que apontam para ele usam RESTRICT.
-- O índice FULLTEXT serve a busca "por tema ou palavra-chave".
-- ---------------------------------------------------------------------
CREATE TABLE tema (
    id_tema         INT UNSIGNED  NOT NULL AUTO_INCREMENT,
    id_admin        INT UNSIGNED  NOT NULL,
    titulo          VARCHAR(255)  NOT NULL,
    palavras_chave  VARCHAR(255)  NULL,
    em_destaque     BOOLEAN       NOT NULL DEFAULT FALSE,
    ativo           BOOLEAN       NOT NULL DEFAULT TRUE,
    criado_em       DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT pk_tema PRIMARY KEY (id_tema),
    CONSTRAINT fk_tema_admin FOREIGN KEY (id_admin)
        REFERENCES administrador (id_admin)
        ON DELETE RESTRICT ON UPDATE CASCADE,
    INDEX idx_tema_ativo_destaque (ativo, em_destaque),
    FULLTEXT INDEX ft_tema_busca (titulo, palavras_chave)
) ENGINE=InnoDB;

-- ---------------------------------------------------------------------
-- 4. TEXTO_MOTIVADOR (Texto I, Texto II, ...)
-- Um tema tem vários textos; "ordem" define se é o I, o II, o III...
-- Se o tema for apagado, seus textos vão junto (CASCADE).
-- ---------------------------------------------------------------------
CREATE TABLE texto_motivador (
    id_texto  INT UNSIGNED      NOT NULL AUTO_INCREMENT,
    id_tema   INT UNSIGNED      NOT NULL,
    ordem     TINYINT UNSIGNED  NOT NULL,
    conteudo  TEXT              NOT NULL,
    fonte     VARCHAR(255)      NULL,
    CONSTRAINT pk_texto_motivador PRIMARY KEY (id_texto),
    CONSTRAINT uq_texto_ordem UNIQUE (id_tema, ordem),
    CONSTRAINT fk_texto_tema FOREIGN KEY (id_tema)
        REFERENCES tema (id_tema)
        ON DELETE CASCADE ON UPDATE CASCADE,
    CONSTRAINT ck_texto_ordem CHECK (ordem >= 1)
) ENGINE=InnoDB;

-- ---------------------------------------------------------------------
-- 5. REDACAO
-- Regra: iniciada_em e tempo_segundos só existem nas redações digitadas;
--        nas enviadas em PDF ficam NULL.
-- Regra: se o aluno excluir a conta, as redações dele são apagadas (CASCADE).
-- ---------------------------------------------------------------------
CREATE TABLE redacao (
    id_redacao      INT UNSIGNED  NOT NULL AUTO_INCREMENT,
    id_aluno        INT UNSIGNED  NOT NULL,
    id_tema         INT UNSIGNED  NOT NULL,
    tipo_envio      ENUM('digitada','pdf') NOT NULL,
    texto           TEXT          NOT NULL,
    iniciada_em     DATETIME      NULL,
    enviada_em      DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP,
    tempo_segundos  INT UNSIGNED  NULL,
    status          ENUM('aguardando_correcao','corrigida','erro_na_correcao')
                    NOT NULL DEFAULT 'aguardando_correcao',
    CONSTRAINT pk_redacao PRIMARY KEY (id_redacao),
    CONSTRAINT fk_redacao_aluno FOREIGN KEY (id_aluno)
        REFERENCES aluno (id_aluno)
        ON DELETE CASCADE ON UPDATE CASCADE,
    CONSTRAINT fk_redacao_tema FOREIGN KEY (id_tema)
        REFERENCES tema (id_tema)
        ON DELETE RESTRICT ON UPDATE CASCADE,
    CONSTRAINT ck_redacao_tempo CHECK (
        (tipo_envio = 'pdf'      AND iniciada_em IS NULL AND tempo_segundos IS NULL)
     OR (tipo_envio = 'digitada' AND iniciada_em IS NOT NULL AND tempo_segundos IS NOT NULL)
    ),
    INDEX idx_redacao_aluno_data (id_aluno, enviada_em),
    INDEX idx_redacao_status (status)
) ENGINE=InnoDB;

-- ---------------------------------------------------------------------
-- 6. COMPETENCIA (5 linhas fixas, carregadas no fim do script)
-- ---------------------------------------------------------------------
CREATE TABLE competencia (
    id_competencia  TINYINT UNSIGNED  NOT NULL,
    nome            VARCHAR(100)      NOT NULL,
    descricao       TEXT              NOT NULL,
    CONSTRAINT pk_competencia PRIMARY KEY (id_competencia),
    CONSTRAINT ck_competencia_id CHECK (id_competencia BETWEEN 1 AND 5)
) ENGINE=InnoDB;

-- ---------------------------------------------------------------------
-- 7. CORRECAO (no máximo uma por redação: UNIQUE em id_redacao)
-- Regra: nota total de 0 a 1000, em múltiplos de 40 (como no ENEM).
-- ATENÇÃO: nota_total é a SOMA das 5 notas de nota_competencia.
--          O sistema deve gravá-la já calculada.
-- ---------------------------------------------------------------------
CREATE TABLE correcao (
    id_correcao        INT UNSIGNED       NOT NULL AUTO_INCREMENT,
    id_redacao         INT UNSIGNED       NOT NULL,
    nota_total         SMALLINT UNSIGNED  NOT NULL,
    feedback_geral     TEXT               NOT NULL,
    corrigida_em       DATETIME           NOT NULL DEFAULT CURRENT_TIMESTAMP,
    email_enviado_em   DATETIME           NULL,
    visualizada_em     DATETIME           NULL,
    CONSTRAINT pk_correcao PRIMARY KEY (id_correcao),
    CONSTRAINT uq_correcao_redacao UNIQUE (id_redacao),
    CONSTRAINT fk_correcao_redacao FOREIGN KEY (id_redacao)
        REFERENCES redacao (id_redacao)
        ON DELETE CASCADE ON UPDATE CASCADE,
    CONSTRAINT ck_correcao_nota CHECK (nota_total BETWEEN 0 AND 1000
                                       AND MOD(nota_total, 40) = 0)
) ENGINE=InnoDB;

-- ---------------------------------------------------------------------
-- 8. NOTA_COMPETENCIA (tabela associativa: correcao x competencia)
-- Chave primária composta: uma nota por competência em cada correção.
-- Regra: nota de 0 a 200, em múltiplos de 40 (0, 40, 80, 120, 160, 200).
-- ---------------------------------------------------------------------
CREATE TABLE nota_competencia (
    id_correcao     INT UNSIGNED       NOT NULL,
    id_competencia  TINYINT UNSIGNED   NOT NULL,
    nota            SMALLINT UNSIGNED  NOT NULL,
    comentario      TEXT               NULL,
    CONSTRAINT pk_nota_competencia PRIMARY KEY (id_correcao, id_competencia),
    CONSTRAINT fk_nota_correcao FOREIGN KEY (id_correcao)
        REFERENCES correcao (id_correcao)
        ON DELETE CASCADE ON UPDATE CASCADE,
    CONSTRAINT fk_nota_competencia FOREIGN KEY (id_competencia)
        REFERENCES competencia (id_competencia)
        ON DELETE RESTRICT ON UPDATE CASCADE,
    CONSTRAINT ck_nota_valor CHECK (nota BETWEEN 0 AND 200 AND MOD(nota, 40) = 0)
) ENGINE=InnoDB;

-- ---------------------------------------------------------------------
-- 9. DICA (escritas pela equipe; a Mila escolhe pela nota do aluno)
-- A faixa [nota_minima, nota_maxima] diz para quem a dica serve.
-- ---------------------------------------------------------------------
CREATE TABLE dica (
    id_dica         INT UNSIGNED       NOT NULL AUTO_INCREMENT,
    id_competencia  TINYINT UNSIGNED   NOT NULL,
    titulo          VARCHAR(150)       NOT NULL,
    conteudo        TEXT               NOT NULL,
    nota_minima     SMALLINT UNSIGNED  NOT NULL,
    nota_maxima     SMALLINT UNSIGNED  NOT NULL,
    CONSTRAINT pk_dica PRIMARY KEY (id_dica),
    CONSTRAINT fk_dica_competencia FOREIGN KEY (id_competencia)
        REFERENCES competencia (id_competencia)
        ON DELETE RESTRICT ON UPDATE CASCADE,
    CONSTRAINT ck_dica_faixa CHECK (nota_minima <= nota_maxima AND nota_maxima <= 200),
    INDEX idx_dica_busca (id_competencia, nota_minima, nota_maxima)
) ENGINE=InnoDB;

-- ---------------------------------------------------------------------
-- TRIGGER: idade mínima de 16 anos no cadastro
-- (CHECK não aceita CURDATE(), por isso a regra fica em um trigger)
-- ---------------------------------------------------------------------
DELIMITER $$
CREATE TRIGGER trg_aluno_idade_minima
BEFORE INSERT ON aluno
FOR EACH ROW
BEGIN
    IF TIMESTAMPDIFF(YEAR, NEW.data_nascimento, CURDATE()) < 16 THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Cadastro permitido apenas para maiores de 16 anos.';
    END IF;
END$$
DELIMITER ;

-- ---------------------------------------------------------------------
-- DADOS INICIAIS: as 5 competências do ENEM
-- ---------------------------------------------------------------------
INSERT INTO competencia (id_competencia, nome, descricao) VALUES
(1, 'Domínio da norma culta',
    'Uso correto da modalidade escrita formal da língua portuguesa.'),
(2, 'Compreensão da proposta',
    'Entendimento do tema e desenvolvimento dele dentro do texto dissertativo-argumentativo.'),
(3, 'Argumentação',
    'Seleção, organização e interpretação de informações e argumentos em defesa de um ponto de vista.'),
(4, 'Coesão textual',
    'Uso dos mecanismos linguísticos que ligam as partes do texto e sustentam a argumentação.'),
(5, 'Proposta de intervenção',
    'Elaboração de uma proposta de solução para o problema, respeitando os direitos humanos.');
