# Înainte de publicare

Acesta este folderul complet care se încarcă în rădăcina repository-ului GitHub.

Pentru salvare comună între telefoane:

1. Creează un proiect gratuit Supabase.
2. Rulează `supabase/setup.sql` în SQL Editor și păstrează privat codul de 64 de caractere returnat.
3. Completează `config.js` cu Project URL și cheia publică Publishable/anon din Supabase.
4. Încarcă **conținutul** acestui folder în GitHub și activează Pages din `main / (root)`.

Nu introduce codul privat în `config.js` sau în GitHub. Codul privat se introduce în aplicație, pe fiecare telefon.

După publicare, ambele telefoane trebuie să folosească același link și același cod privat. Salvarea se face în Supabase prin internet, deci telefoanele pot fi pe rețele diferite și în locații diferite.

Aplicația afișează „Buget comun” când sincronizarea este activă. Dacă afișează „Mod local”, datele rămân numai pe dispozitivul respectiv.
