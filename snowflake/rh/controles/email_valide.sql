-- Règle de qualité email_valide (contrat, section 6) : l'e-mail contient un @.
-- Une ligne, une colonne : le nombre de chauffeurs dont l'e-mail n'a pas de @, e-mail vide compris.
-- Seuil : 0. Dépassement : avertissement (ligne ALERTE, les tâches continuent).
-- COUNT(*) moins les e-mails valides, plutôt que COUNT_IF(email NOT LIKE '%@%') : celui-ci ignorerait un e-mail NULL.
SELECT COUNT(*) - COUNT_IF(email LIKE '%@%') AS nb_anomalies
FROM NYC_TAXI.RAW.DRIVERS;
