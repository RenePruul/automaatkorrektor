# Automaatkorrektor

macOS-i rakendus

## Kasutamine

Vajalik on macOS 15 või uuem ja eraldi töötav
[Eesti keele tuvastaja](https://github.com/RenePruul/eesti-keele-tuvastaja).

1. Käivita kohalik keeleteenus:

   ```bash
   cd /tee/eesti-keele-tuvastaja
   .venv/bin/keele-api
   ```

2. Ava Automaatkorrektor ja anna sellele luba asukohas **System Settings →
   Privacy & Security → Accessibility**.
3. Vali TextEditis, Safaris või Chrome'is tekst.
4. Vali menüüribalt **Kontrolli valitud teksti** või kasuta kiirklahvi.

Vaikimisi kasutatakse kohalikku API-t aadressil `http://127.0.0.1:8000`.

## Arendamine

Vajalik on Xcode 26 või uuem ja Swift 6.2.

```bash
export DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer"
swift test
```

## Litsents

[MIT](LICENSE)
