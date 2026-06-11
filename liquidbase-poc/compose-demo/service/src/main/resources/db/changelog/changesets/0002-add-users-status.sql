--liquibase formatted sql

--changeset kk:0002-add-users-status
ALTER TABLE users ADD status NVARCHAR(50) NOT NULL CONSTRAINT df_users_status DEFAULT 'active';
--rollback ALTER TABLE users DROP CONSTRAINT df_users_status;
--rollback ALTER TABLE users DROP COLUMN status;
