
-- Backward-compatible view so old code querying gmail_connections still works
-- after the table was renamed to email_connections
CREATE OR REPLACE VIEW gmail_connections AS SELECT * FROM email_connections;

