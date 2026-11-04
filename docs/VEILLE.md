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

### Fiche 1 — <titre>

- **Source** : <organisme, titre, lien>
- **Date** : <publication> · consultée le <date>
- **Ce que dit le texte** : <en trois phrases au plus, avec vos mots>
- **Ce que cela change pour notre entrepôt** : <tables, colonnes, rôles ou règles concernés>
- **Action** : <aucune / à faire dans ce brief / à signaler à la direction>

<!-- Copier la fiche pour les suivantes -->

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
