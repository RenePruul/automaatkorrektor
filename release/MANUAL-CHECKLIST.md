# macOS v0.1 väljalaske käsikontroll

Kasuta ainult sünteetilist teksti ja keeleteenuse teststub'i. Ära kleebi
isiklikku teksti, paroole, pääsmikke ega privaatsusnäite väärtust tõendifaili
või raportisse.

Esmalt loo kandidaat käsuga `scripts/build-release-candidate.sh --tag TAG`.
Kopeeri `release/manual-evidence.example.tsv` väljapoole Giti jälgimist ja
asenda kaks `Candidate-*` päise kohatäitjat loodud faili
`.candidate-metadata.txt` täpsete väärtustega. Asenda rea `PENDING` olek alles
pärast selle kontrollimist täpselt sama kandidaadiga. Seejärel käivita:

```sh
scripts/release-gate.sh \
  --manual-evidence .release-evidence/manual.tsv \
  --report .release-evidence/report.md
```

Käsk lõpetab olekukoodiga 2, kuni kõik 35 nõutavat rida on läbitud. Ära
finaliseeri veel ega eelda lõplike väljalaskefailide olemasolu. Kui kõik read
on läbitud, kasuta selle juhendi lõpus olevat finaliseerimise ja lõppfailide
kontrolli jaotist.

## Loodud DMG paigaldustee

Tee see kontroll skriptiga `scripts/build-release-candidate.sh` loodud DMG-ga,
mitte Xcode'ist või DerivedData kaustast käivitatud rakendusega.

1. Ava kandidaadi `.candidate-metadata.txt`. Tõendi-TSV väärtused
   `Candidate-Tag` ja `Candidate-Commit` peavad võrduma metaandmete väärtustega
   `Tag` ja `Commit`. Käsk `git rev-parse 'TAG^{commit}'` peab kuvama sama
   commit'i. Lõplikke väljalaske metaandmeid selles etapis veel pole.
2. Ava DMG, veendu, et see sisaldab ainult oodatud rakendust, ja kopeeri
   Automaatkorrektor kausta `/Applications`.
3. Käivita paigaldatud rakendus. Kontrolli oodatud Gatekeeperi voogu järgu
   puhul, mis pole Developer ID-ga allkirjastatud ega Apple'i notariseeritud.
   Ava rakendus ainult Control-klõpsu → **Open** või **System Settings → Privacy
   & Security → Open Anyway** abil. Ära lülita Gatekeeperit kogu süsteemis välja.
4. Anna paigaldatud rakendusele Accessibility-luba. Kui varasema ad-hoc-järgu
   luba on aegunud, eemalda selle Accessibility-kirje, lisa paigaldatud rakendus,
   luba see ja ava rakendus uuesti.
5. Käivita kohalik keeleteenus eraldi aadressil `http://127.0.0.1:8000` ja tee
   TextEditis üks selgelt algatatud kontroll. Veendu, et teenus saab ühe päringu
   ja rakendus kuvab oodatud otsuse.

Salvesta ainult artefakti versioon, tägi, operatsioonisüsteemi versioon,
kasutatud taastamisteed ja tulemus. Ära salvesta valitud teksti. Sellega on
`manual-dmg-install` täidetud; artefakti ei laadita üles ega muudeta välist
teenust.

## Võrguühenduseta keeleteenuse teststub

`tools/language_api_stub.py` on ainult testimiseks mõeldud taristu. See kasutab
ainult Pythoni standardteeki, kuulab üksnes aadressil `127.0.0.1` ja võtab vastu
täpselt päringu `POST /detect` sisuga `{"text":"..."}`. Päringukehi ei
salvestata ega väljastata. Sündmuse väljund sisaldab ainult päringute arvu,
keha baitide arvu, väljanimetusi ja valikulist privaatsusnäite vaste tõeväärtust.

Käivita kliendi vaikimisi aadressil üks kindel otsus:

```sh
AUTOMAATKORREKTOR_STUB_PORT=8000 \
AUTOMAATKORREKTOR_STUB_VERDICT=jah \
python3 tools/language_api_stub.py
```

Teiste otsuste kontrollimiseks käivita stub uuesti väärtusega `ei` või
`ebakindel`. Taastumiskäitumist saab kontrollida järgmiste vastuse- ja
viivitusrežiimidega:

```sh
# Kliendi kolmesekundiline ajalimiit; ühenduse katkestamine on oodatud.
AUTOMAATKORREKTOR_STUB_PORT=8000 \
AUTOMAATKORREKTOR_STUB_DELAY_SECONDS=4 \
python3 tools/language_api_stub.py

# Tundmatu otsus ehk ühildumatu teenus.
AUTOMAATKORREKTOR_STUB_PORT=8000 \
AUTOMAATKORREKTOR_STUB_RESPONSE=incompatible \
python3 tools/language_api_stub.py

# HTTP 503 ehk kättesaamatu server.
AUTOMAATKORREKTOR_STUB_PORT=8000 \
AUTOMAATKORREKTOR_STUB_RESPONSE=server-error \
python3 tools/language_api_stub.py
```

Kontrolli töötamise ajal privaatsust hoidvat ajutist olekut käsuga:

```sh
curl --fail --silent http://127.0.0.1:8000/_test/status
```

Vastus sisaldab `request_count` väärtust ja lubatud metaandmeid, kuid mitte
kunagi valitud teksti. Peata stub klahvikombinatsiooniga Control-C. Ära suuna
stub'i väljundit faili.

## Ainult testimiseks mõeldud Accessibility testirakendused

Tootmisrakenduse Automaatkorrektor lubatud rakendused on endiselt ainult
TextEdit, Safari ja Chrome. Rakendus peab `NativeTextControlHost` hosti tagasi
lükkama; see host on lubatud ainult eraldi kompileeritud testirakenduse reeglis.
Kumbki testirakendus ei tee võrgupäringut ega kuva, logi või salvesta valitud
teksti.

Ehita ja ava mõlemad korrektselt pakitud testirakendused täpse käsuga:

```sh
scripts/run-native-ax-harness.sh
```

1. Anna rakendusele **AX Integration Harness** süsteemiseadetes
   Accessibility-luba. Ära kasuta keskkonnamuutujat ega muuda tootmisrakendust.
2. Iga testirea puhul klõpsa **Käivita kontroll** ja seejärel viie sekundi
   jooksul rakenduses **Native Text Control Host** vastavat nuppu **Valmista
   ette**. Host fokuseerib juhtelemendi ja valib ainult sünteetilise prooviteksti.
3. Nõua ainult metaandmetega `PASS` tulemust muudetavale `NSTextField`,
   `NSSearchField` ja `NSTextView` väljale.
4. Nõua ainult metaandmetega `PASS` tulemust kirjutuskaitstud, keelatud ja
   turvalise välja tagasilükkamisele. Keele-API-t ega stub'i ei kasutata.
5. Käivita tootmisrakendus eraldi, vali hostis sünteetiline tekst ja veendu, et
   tootmisklient lükkab hosti tagasi enne stub-päringut.

Tõend `integration-native-host` jääb olekusse `PENDING`, kuni kõik seitse
tulemust on väljalaskekandidaadil kontrollitud. Salvesta ainult rakenduste
versioonid, kuus testirakenduse `PASS` olekut, tootmisrakenduse tagasilükkamine,
operatsioonisüsteemi versioon ja kuupäev — mitte kunagi prooviteksti.

## TextEdit

1. Anna tootmisrakendusele Automaatkorrektor süsteemiseadetes
   Accessibility-luba.
2. Kontrolli TextEditis, et sünteetilise teksti selge valik annaks kõik otsused
   `jah`, `ei` ja `ebakindel`. Tühi valik ja fookuse muutus ei tohi päringut teha.

## Safari ja Chrome

1. Ava fail `Tests/AutomaatkorrektorMacOSTests/Fixtures/browser-fields.html`
   mõlemas brauseris kohalikult. Ära jaga seda internetist.
2. Kontrolli, et teksti-, otsingu- ja `textarea`-välja valik annaks stub'i otsuse.
3. Kontrolli, et parooli-, kirjutuskaitstud, keelatud ja `contenteditable` juht
   ei teeks päringut. Ära loe brauseri kasutajaliidest, näiteks aadressiriba,
   lehe tekstivälja tõendiks.

## Luba ja kasutamine

1. Keelatud Accessibility-loa korral kontrolli blokeeritud vaadet ja
   nummerdatud taastamisjuhiseid. Stub-päringut ei tohi tekkida.
2. Anna luba ja kontrolli uuesti. Roheline valmisolek peab ilmuma rakendust
   taaskäivitamata.
3. Alusta viivitusega kontrolli, tühista luba ja veendu, et kontroll katkeb ilma
   teise päringuta.
4. Võrdle menüütoimingut ja globaalset kiirklahvi: mõlemad peavad avama
   hüpikvaate, näitama kontrollimist ning jätma nähtavaks sama otsuse või
   stabiilse vea.
5. Kontrolli ajalimiidi, kättesaamatu teenuse ja ühildumatu vastuse vaateid.
   Hüpikvaate sulgemine viivitusega päringu ajal peab katkestama vaikselt.

## Privaatsusnäide

1. Kirjuta sobivale sünteetilisele väljale kordumatu väärtus, mis algab
   `AUTOMAATKORREKTOR-PRIVACY-CANARY-`, kuid ära käivita veel kontrolli. Ära
   kasuta lõikelauda.
2. Sisesta sama väärtus terminali kajata ja arvuta ajutisse keskkonnamuutujasse
   ainult selle räsi:

   ```sh
   IFS= read -r -s canary_value
   export AUTOMAATKORREKTOR_STUB_CANARY_SHA256="$(printf %s "$canary_value" | shasum -a 256 | awk '{print $1}')"
   unset canary_value
   AUTOMAATKORREKTOR_STUB_PORT=8000 python3 tools/language_api_stub.py
   ```

3. Tee täpselt üks kontroll. Küsi `/_test/status` ja nõua `request_count: 1`
   ning `canary_match: true`. Stub võrdleb SHA-256 räsisid ega säilita või
   väljasta täielikku väärtust.
4. Veendu, et täielik väärtus ei esine päringu URL-is, päistes, rakenduse
   vaates, seadetes, ühendlogis, failides, vahemäludes, krahhiraportites,
   ajaloos ega loodud väljalaskeraportis.
5. Peata stub, eemalda `AUTOMAATKORREKTOR_STUB_CANARY_SHA256` ja salvesta ainult
   tulemus koos neutraalse tõendimärkusega. Ära kopeeri väärtust või selle räsi
   TSV-faili või raportisse.

## Keelekontrolli nõusoleku privaatsustee

Kasuta operaatori hallatavat ühilduvat HTTPS-kaugfixture'it, mille päringukeha
ei logita ega säilitata. See tohib näidata ainult ajutist päringute arvu,
vastuvõetud JSON-väljade nimesid, keha baitide arvu ja privaatsusnäite räsi
vaste tõeväärtust. Ära kasuta avalikku kolmanda osapoole teenust. Seadista
klient täpselt nõusolekuvaates näidatud fixture'i origin'iga.

1. Sisesta sobivale väljale uus kordumatu sünteetiline väärtus, mis algab
   dokumenteeritud privaatsusnäite prefiksiga. Ära kasuta lõikelauda,
   terminaliargumente, shelli ajalugu, fixture-faili ega tõendi-TSV-d. Anna räsi
   kaugfixture'ile kohaliku protseduuriga samaväärsel kajata ja ajutisel viisil.
2. Salvesta fixture'i ainult metaandmetega päringute algarv. Käivita selge
   kontroll ja vali **Loobu**. Päringute arv ei tohi muutuda ning klient ei
   tohi valitud teksti lugeda või kuvada.
3. Käivita uus kontroll, veendu, et kuvatud origin vastab täpselt seadistatud
   HTTPS-origin'ile, ja vali **Luba ja kontrolli**. Päringute arv peab suurenema täpselt ühe
   võrra, `canary_match` peab olema `true` ning ainus JSON-väli peab olema
   `text`. Fixture ei tohi näha päringut ühelegi teisele origin'ile.
4. Muuda seadistatud teenus teise HTTPS-origin'i vastu. Nõua uut nõusolekuvaadet
   ja enne otsust mitte ühtegi päringut. Taasta algne teenus alles pärast ainult
   metaandmetega tulemuse salvestamist.
5. Tühista salvestatud keelekontrolli nõusolek seadetes. Käivita uus kontroll,
   vali **Loobu** ja nõua, et päringute arv ei muutuks.
6. Peata fixture ja eemalda ajutine privaatsusnäite räsi. Otsi täielikku
   väärtust rakenduse vaatest, seadetest, ühendlogist, loodud raportist ja
   väljalaskefailidest; seda ei tohi leiduda. Ära lisa täielikku väärtust või
   selle räsi raportisse, commit'itud fixture'isse, kuvatõmmisele või
   tõendimärkusesse.

Salvesta `manual-language-check-consent` puhul ainult kuvatud origin,
päringute arvu muutused, testitud rakenduse versioon, kuupäev ja tulemus. See
kontroll tõendab, et keeldumine ei saada kaugpäringut ning lubamine saadab
kuvatud origin'ile ainult valitud välja `text`.

## Operatsioonisüsteemi ja API piirid

1. Tee põhiline käsikontroll arendus-Macis, kus töötab macOS 15 või uuem.
2. Salvesta neutraalsetesse märkustesse operatsioonisüsteemi ning Safari ja
   Chrome'i versioonid.
3. Kasuta nimetatud keele-API commit'i. Kinnita täpselt `POST /detect`, ainult
   välja `text` sisaldav JSON-päring ning vastuse otsused `jah`, `ei` ja
   `ebakindel`. Salvesta API commit, mitte kunagi päringu või vastuse sisu.
4. Veendu, et väljalaskemärkmed lubavad ainult TextEditi ja standardseid Safari
   või Chrome'i välju. Ära luba Maili, rikasteksti redaktoreid, parandamist,
   passiivset jälgimist, Windowsit, sisselogimisel käivitamist või
   tootmiskasutuseks levitamist.

## Finaliseeritud väljalaske kontroll

See jaotis ei ole ühegi käsitõendi rea eeltingimus. Kasuta seda alles siis, kui
tõendifail nimetab kandidaadi ja kõik 35 nõutavat kontrolli on läbitud.
Finaliseeri juba testitud kandidaat seda uuesti ehitamata:

```sh
scripts/finalize-release-dmg.sh \
  --candidate .release-evidence/candidates/Automaatkorrektor-v0.1.0.dmg \
  --manual-evidence .release-evidence/manual.tsv
```

Edutatud DMG peab olema testitud kandidaadiga bait-baidilt identne. Pärast
edutamist kontrolli lõppfaile kaustas `.release-evidence/releases/`:

```sh
cat .release-evidence/releases/Automaatkorrektor-v0.1.0.release-metadata.txt
git rev-parse 'v0.1.0^{commit}'
```

Lõplike metaandmete `Tag` ja `Commit` peavad vastama täpsele Git-tägile ja
lahendatud commit'ile. Väljalaskejärgne kontroll ei muuda ega lisa
käsitõendeid.
