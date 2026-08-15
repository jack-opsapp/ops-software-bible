ALTER TABLE agent_writing_profiles
    ADD COLUMN profile_type TEXT NOT NULL DEFAULT 'general';

ALTER TABLE agent_writing_profiles
    DROP CONSTRAINT agent_writing_profiles_company_id_user_id_key;

ALTER TABLE agent_writing_profiles
    ADD CONSTRAINT agent_writing_profiles_company_user_type_key
    UNIQUE (company_id, user_id, profile_type);
