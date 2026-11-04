# Note de veille réglementaire — données du personnel de Hudson Cab Partners

Une veille n'est pas une recherche faite une fois : c'est un dispositif qui continue de vous prévenir quand un texte change. Chaque affirmation de cette note cite sa source (texte, article, date de publication ou de consultation).

## 1. Le droit applicable

Le traitement : les données de chauffeurs employés à New York, gérées depuis Paris par Hudson Cab Europe, à qui le groupe a confié leur gestion.

| Question | Réponse | Source (texte et article) |
|---|---|---|
| Le RGPD s'applique-t-il à ce traitement ? | Oui | RGPD, art. 3 § 1 (CNIL, chapitre 1, consulté le 2026-11-02) |
| Pourquoi, alors que les chauffeurs ne sont pas en Europe ? | L'article 3 § 1 regarde **où est établi celui qui décide**, pas où vivent les personnes. **Hudson Cab Europe décide et est à Paris : le RGPD s'applique**, même si les chauffeurs sont à New York. | Même source |
| Qui est responsable du traitement ? Qui est sous-traitant ? | **Responsable du traitement : Hudson Cab Europe** (Paris), qui décide des finalités (gérer le personnel des trois dépôts) et des moyens (l'entrepôt Snowflake, les règles d'accès, de masquage et de conservation). **Sous-traitant : Snowflake**, qui héberge et exécute pour le compte du responsable, sans rien décider. Hudson Cab Partners (New York), l'employeur, fournit les fichiers mais ne décide pas du traitement dans l'entrepôt : pour ce traitement-ci, il n'est ni responsable ni sous-traitant (une responsabilité conjointe, art. 26, n'est pas exclue ; question laissée ouverte en section 5). | RGPD, art. 4 points 7 et 8 (CNIL, chapitre 1) ; art. 28 § 1 et § 3 pour les obligations du sous-traitant (CNIL, chapitre 4), consultés le 2026-11-02 |
| Quelle autorité de contrôle est compétente ? | **La CNIL.** Le responsable du traitement est établi en France ; l'autorité française est compétente sur son territoire. L'article 56 (autorité « chef de file ») ne joue pas : Hudson Cab Europe n'a qu'un établissement dans l'Union, le traitement n'est pas transfrontalier. | RGPD, art. 55 § 1 et art. 56 § 1 (CNIL, chapitre 6, consulté le 2026-11-02) |

## 2. Le dispositif de veille

| Source | Type (officielle, professionnelle…) | Ce qu'on y surveille | Fréquence | Outil de suivi |
|---|---|---|---|---|
| CNIL, flux « Actualités » (`https://www.cnil.fr/fr/rss.xml`) | Officielle : l'autorité de contrôle compétente (section 1) | Délibérations et sanctions, recommandations et référentiels (gestion du personnel, durées de conservation), mises à jour des guides. Touche R1, le registre et la matrice des accès. | Hebdomadaire | Feedly, dossier « Veille RGPD RH » |
| CEPD, flux « Actualités » en français (`https://www.edpb.europa.eu/feed/news_fr`) | Officielle : l'organe qui réunit les autorités de contrôle de l'Union | Lignes directrices et avis sur les notions du RGPD : sous-traitant (art. 28), responsabilité conjointe (art. 26), transferts hors de l'Union. Touche la section 1 et la question ouverte de la section 5. | Hebdomadaire | Feedly, même dossier |
| Snowflake, notes de version (`https://docs.snowflake.com/en/release-notes/new-features`) | Professionnelle : l'éditeur, notre sous-traitant | Nouveautés et changements sur les politiques de masquage et d'accès par ligne, les tags, le Time Travel (R2), les tâches ; dépréciations qui casseraient les scripts. | Mensuelle | Favori du navigateur, dossier « Veille RGPD RH » (pas de flux RSS) |

Capture du dispositif : `capture_veille_feedly.png`.

Qui, dans le binôme puis dans l'équipe, lit la veille et décide qu'une nouveauté demande une action : le binôme est ici un humain et un assistant IA (Claude), l'humain restant dans la boucle à chaque décision. Greg lit Feedly chaque lundi et les notes de version Snowflake une fois par mois ; quand une nouveauté semble toucher une règle du contrat, une table du registre ou un rôle de la matrice des accès, il la soumet à l'assistant, qui évalue l'impact sur les scripts et les tests et propose un brouillon de fiche (section 3) ; Greg décide seul de l'action, relit tout ce que l'assistant écrit et commite. Dans l'équipe, le même partage vaut : l'ingénieur données lit la veille et pilote l'assistant, le délégué à la protection des données décide ; chaque action retenue donne une fiche en section 3 et, s'il y a écart avec le contrat, une ligne dans le README.

## 3. Les fiches de veille

Au moins quatre fiches. Une fiche = un texte, une recommandation ou une décision.

### Fiche 1 — Les durées de conservation : une durée par finalité, et trois phases de vie

- **Source** : CNIL, « Les durées de conservation des données », https://www.cnil.fr/fr/les-durees-de-conservation-des-donnees
- **Date** : 2 avril 2026 · consultée le 2026-11-02
- **Ce que dit le texte** : C'est au responsable du traitement de fixer la durée de conservation, en fonction de l'objectif qui a justifié la collecte, avant de commencer à traiter (RGPD, art. 5 § 1 e). La donnée vit en trois phases : la base active tant qu'elle sert à l'objectif, l'archivage intermédiaire quand le dossier est clos mais qu'une obligation légale ou un contentieux possible impose de la garder, l'archivage définitif, rare ; les deux dernières phases ne sont pas automatiques et l'archive doit être séparée de la base active, physiquement ou par les habilitations. Quand la durée n'est pas fixée par un texte, la CNIL publie des durées recommandées : les appliquer vaut présomption de conformité, s'en écarter se documente.
- **Ce que cela change pour notre entrepôt** : La règle R1 (« supprimées 5 ans après la fin du contrat ») et le tag `DUREE_CONSERVATION` posé sur `RAW.DRIVERS`, `RAW.DRIVER_SHIFTS`, `MARTS.DIM_DRIVER` et `MARTS.MART_DRIVER_MONTHLY` ne distinguent pas les phases : un chauffeur parti reste cinq ans dans la base active, lisible par `RH_PAIE` et par le responsable de son dépôt, avec les mêmes droits qu'un chauffeur en poste. La CNIL attend qu'un dossier clos soit isolé, au moins logiquement (droits restreints). La purge à cinq ans (`T_PURGE`) traite la fin de vie, pas la phase intermédiaire.
- **Action** : à signaler à la direction. Soit elle assume cinq ans en base active, soit elle demande un archivage intermédiaire (une politique d'accès par ligne sur `end_date` qui réserve les chauffeurs partis à `RH_PAIE` en est une mise en œuvre possible). Hors périmètre du contrat tel qu'écrit ; ligne reportée dans la section 4.

### Fiche 2 — Le registre des activités de traitement (art. 30)

- **Source** : CNIL, « Le registre des activités de traitement », https://www.cnil.fr/fr/RGPD-le-registre-des-activites-de-traitement ; RGPD, art. 30 § 1
- **Date** : 13 avril 2018 · consultée le 2026-11-02
- **Ce que dit le texte** : Tout organisme qui traite des données personnelles tient un registre écrit, communicable à la CNIL, avec pour chaque traitement : la finalité, les catégories de personnes et de données, les destinataires (sous-traitants compris), les transferts hors de l'Union, les délais d'effacement et une description des mesures de sécurité. Le registre doit refléter la réalité et être mis à jour à chaque changement : nouvelle donnée collectée, durée allongée, nouveau destinataire. Un sous-traitant tient son propre registre des traitements faits pour ses clients.
- **Ce que cela change pour notre entrepôt** : `docs/REGISTRE.md` est ce registre pour le traitement « gestion du personnel des dépôts ». Sa partie 1 (inventaire des colonnes personnelles de `RAW.DRIVERS` et `RAW.DRIVER_SHIFTS`, où elles sont copiées) couvre les catégories de données. Les autres rubriques de l'article 30 ont déjà un répondant technique qu'il suffit de nommer : les destinataires sont les rôles de la matrice des accès plus Snowflake (sous-traitant) ; le délai d'effacement est le tag `DUREE_CONSERVATION` ; les mesures de sécurité sont les politiques de masquage et d'accès par ligne et l'audit `ACCESS_HISTORY`. La règle de mise à jour vaut pour le catalogue : toute colonne ajoutée à une table RH doit être cataloguée et, si elle est personnelle, taguée, sinon le registre ment. Les données viennent de New York : le transfert est entrant (pays tiers vers l'Union), il n'est pas régi par le chapitre V, mais la rubrique « transferts » doit le dire.
- **Action** : à faire dans ce brief. Compléter `REGISTRE.md` avec finalité, destinataires, délais et mesures, en renvoyant au catalogue plutôt qu'en recopiant.

### Fiche 3 — Le champ d'application territorial (art. 3) : ce qui compte est l'établissement, pas le lieu des personnes

- **Source** : CEPD, « Lignes directrices 3/2018 relatives au champ d'application territorial du RGPD (article 3) », version 2.0, https://www.edpb.europa.eu/our-work-tools/our-documents/guidelines/guidelines-32018-territorial-scope-gdpr-article-3-version_fr
- **Date** : 12 novembre 2019 · consultée le 2026-11-02
- **Ce que dit le texte** : L'article 3 s'applique traitement par traitement, pas organisme par organisme : un même groupe peut avoir des traitements dans le champ du RGPD et d'autres en dehors. Pour l'article 3 § 1, le CEPD recommande trois questions : qui est responsable ou sous-traitant de ce traitement, a-t-il un établissement dans l'Union (une activité réelle et effective au moyen d'un dispositif stable, quelle que soit la forme juridique), le traitement a-t-il lieu dans le cadre des activités de cet établissement (analyse au cas par cas, lien « inextricable »). Le lieu réel du traitement et le lieu des personnes concernées n'entrent pas dans ces trois questions.
- **Ce que cela change pour notre entrepôt** : Cela confirme la section 1 : Hudson Cab Europe, établie à Paris, décide des finalités et des moyens, donc le RGPD s'applique aux quatre tables du domaine RH, bien que les chauffeurs soient à New York. Deux conséquences que la section 1 ne disait pas : un sous-traitant établi dans l'Union est lui aussi soumis au RGPD pour ce traitement (Snowflake, région de Paris) ; et le lien « inextricable » entre l'établissement parisien et l'employeur américain, s'il est établi, pourrait faire entrer dans le champ du RGPD des traitements que Hudson Cab Partners fait de son côté, hors de notre entrepôt.
- **Action** : aucune dans le brief. La seconde conséquence rejoint la question de la responsabilité conjointe (art. 26) posée en section 5.

### Fiche 4 — Le référentiel CNIL « gestion du personnel » : habilitations, durées, journalisation

- **Source** : CNIL, « Référentiel relatif aux traitements de données à caractère personnel mis en œuvre aux fins de gestion du personnel », https://www.cnil.fr/sites/cnil/files/atoms/files/referentiel_grh_novembre_2019_0.pdf (sections 6, 7 et 10, pages 10 à 13)
- **Date** : adopté le 21 novembre 2019 · consulté le 2026-11-02
- **Ce que dit le texte** : Seules les personnes habilitées au titre de leurs fonctions accèdent aux données du personnel, dans la stricte limite de leurs attributions : la paie, la sécurité, le supérieur hiérarchique de l'employé concerné. Les données de la relation de travail se gardent en base active le temps du contrat, puis en archive intermédiaire à accès restreint le temps des obligations légales ; le tableau cite cinq ans après le départ pour le registre unique du personnel (code du travail, R. 1221-26), cinq ans pour les bulletins de paie, six ans pour les éléments de calcul des cotisations. En sécurité, l'organisme définit des profils d'habilitation, supprime les permissions obsolètes, revoit les habilitations chaque année et journalise les accès.
- **Ce que cela change pour notre entrepôt** : La matrice des accès du contrat est une liste de profils d'habilitation au sens du référentiel : `RH_PAIE` est « la paie », `RESP_DEPOT_QUEENS` et `RESP_DEPOT_BRONX` sont « le supérieur hiérarchique » limité à ses employés (d'où la politique d'accès par ligne sur `depot`), `ANALYSTE` n'a pas de fonction RH, d'où le masquage de tout ce qui identifie (`DONNEE_PERSONNELLE`). La durée de R1 (cinq ans après la fin du contrat) coïncide avec R. 1221-26, mais ce texte ne couvre que les mentions du registre du personnel, c'est-à-dire l'identité et les dates de `RAW.DRIVERS` et `DIM_DRIVER` ; pour les services et les revenus (`RAW.DRIVER_SHIFTS`, `MART_DRIVER_MONTHLY`), la justification serait plutôt celle de la paie (cinq à six ans). La valeur du tag est défendable, sa justification diffère selon la table. La journalisation attendue correspond à l'audit par `ACCESS_HISTORY` ; la revue annuelle des habilitations et la suppression des permissions obsolètes ne figurent pas au contrat.
- **Action** : à faire dans ce brief pour la journalisation (`06_audit.sql`) et pour préciser dans le catalogue la justification de `DUREE_CONSERVATION` par table. À signaler à la direction : une revue annuelle des rôles, absente du contrat.

## 4. Le contrat face aux textes

Une ligne par règle du contrat de gouvernance (accès, conservation, qualité). Vous ne réécrivez pas le contrat : un écart se signale, il se reporte dans le README.

| Règle du contrat | Ce que disent les textes | Source | Conforme ? | Écart et proposition |
|---|---|---|---|---|
| R1 : suppression 5 ans après la fin du contrat | | | | |
| R2 : Time Travel limité à 1 jour | | | | |
| R3 : fichier RH retiré du stage | | | | |
| Matrice des accès (qui voit quoi) | | | | |
| Règles de qualité (contrat, section 6) | | | | |

## 5. Ce que la veille ne tranche pas

Les questions qui demandent l'avis d'un juriste ou du délégué à la protection des données, et à qui vous les poseriez : ______
