--liquibase formatted sql

--changeset kk:0001-create-users
CREATE TABLE users (
    id          BIGINT IDENTITY(1,1) NOT NULL CONSTRAINT pk_users PRIMARY KEY,
    email       NVARCHAR(255) NOT NULL CONSTRAINT uq_users_email UNIQUE,
    created_at  DATETIME2 NOT NULL CONSTRAINT df_users_created_at DEFAULT SYSUTCDATETIME()
);
--rollback DROP TABLE users;
