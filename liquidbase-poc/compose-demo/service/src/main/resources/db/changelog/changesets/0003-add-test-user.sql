--liquibase formatted sql

--changeset kk:0003-add-test-user
ALTER TABLE users ADD dummy NVARCHAR(50);
--rollback ALTER TABLE users DROP COLUMN dummy;
