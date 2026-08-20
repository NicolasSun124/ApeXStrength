-- Idempotent seed data matching the iOS defaultMuscles/defaultTags lists.
-- UUIDs are deterministic so this migration is safe to run repeatedly.
WITH premade(name, color_hex) AS (VALUES
    ('Abdominals', '8AC5FF'), ('Abductors', '8AC5FF'), ('Adductors', '8AC5FF'),
    ('Biceps', '8AC5FF'), ('Calves', '8AC5FF'), ('Forearm Extensors', '8AC5FF'),
    ('Forearm Flexors', '8AC5FF'), ('Front Deltoid', '8AC5FF'), ('Gluteus maximus', '8AC5FF'),
    ('Hamstrings', '8AC5FF'), ('Lateral Deltoid', '8AC5FF'), ('Lats', '8AC5FF'),
    ('Lower Back', '8AC5FF'), ('Lower Chest', '8AC5FF'), ('Lower Traps', '8AC5FF'),
    ('Middle Traps', '8AC5FF'), ('Obliques', '8AC5FF'), ('Quads', '8AC5FF'),
    ('Rear Deltoid', '8AC5FF'), ('Triceps', '8AC5FF'), ('Upper Chest', '8AC5FF'),
    ('Upper Traps', '8AC5FF')
), identified AS (
    SELECT name, color_hex, md5('apexstrength:muscle:' || lower(name)) AS hash FROM premade
)
INSERT INTO muscles (id, name, color_hex)
SELECT (substr(hash, 1, 8) || '-' || substr(hash, 9, 4) || '-5' || substr(hash, 14, 3) ||
        '-a' || substr(hash, 18, 3) || '-' || substr(hash, 21, 12))::uuid,
       name, color_hex
FROM identified
WHERE NOT EXISTS (SELECT 1 FROM muscles m WHERE lower(m.name) = lower(identified.name));

WITH premade(name) AS (VALUES
    ('Upper'), ('Lower'), ('Core'), ('Push'), ('Pull'), ('Legs'), ('Back'), ('Chest'),
    ('Hypertrophy'), ('Strength'), ('Plyometrics'), ('Calisthenics'), ('Circuit'),
    ('Beginner'), ('Intermediate'), ('Advanced'), ('Endurance'), ('Flexibility'),
    ('Stability'), ('Cardio'), ('Functional'), ('Bodyweight')
), seeds AS (
    SELECT u.id AS user_id, p.name,
           md5('apexstrength:tag:' || u.id::text || ':' || lower(p.name)) AS hash
    FROM users u CROSS JOIN premade p
)
INSERT INTO tags (id, user_id, client_uuid, name)
SELECT (substr(hash, 1, 8) || '-' || substr(hash, 9, 4) || '-5' || substr(hash, 14, 3) ||
        '-a' || substr(hash, 18, 3) || '-' || substr(hash, 21, 12))::uuid,
       user_id,
       substr(hash, 1, 8) || '-' || substr(hash, 9, 4) || '-5' || substr(hash, 14, 3) ||
       '-a' || substr(hash, 18, 3) || '-' || substr(hash, 21, 12),
       name
FROM seeds
WHERE NOT EXISTS (
    SELECT 1 FROM tags t WHERE t.user_id = seeds.user_id AND lower(t.name) = lower(seeds.name)
);
