"""Writes repo/README.md (the extension repository's front page) from repo/index.json.

  python tools/gen_repo_readme.py

Run it after gen_repo.py / probe_sources.py so the source list and the status column stay current.
"""
import collections, json, os

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
REPO = os.path.join(ROOT, "repo")

LANGS = [("all", "Multi-idioma"), ("en", "Inglês"), ("pt-BR", "Português (Brasil)"), ("pt", "Português"),
         ("es", "Espanhol"), ("es-419", "Espanhol (América Latina)"), ("fr", "Francês"), ("de", "Alemão"), ("it", "Italiano")]
STATUS = {"ok": "🟢 funciona", "partial": "🟡 parcial", "dead": "🔴 fora do ar", "relay": "🟡 relay", None: "⚪ não testada"}
ORIGIN = {
    "otakio": "nativa (Otakio)",
    "keiyoushi": "tema keiyoushi",
    "yuzono": "tema yuzono",
    "cursed": "tema cursed",
    "codegeasse": "tema codegeasse",
    "noboru": "parser NOBORU",
}

HEADER = """# Otakio Extensions

Repositório de **extensões (fontes)** para o [Otakio](https://github.com/Garryth69/otakio), leitor de mangá para PS
Vita. O app não vem com nenhuma fonte: elas são instaladas a partir deste repositório, dentro do próprio app.

> *English:* Source extensions for the Otakio manga reader (PS Vita). Add this repository in the app
> (Extensions → Select → Add repository → `Garryth69/otakio-extensions`). No content is hosted here: each extension
> is a small Lua script that reads a third-party website on the user's console.

## Como usar no Vita

1. Instale o Otakio ([Releases do app](https://github.com/Garryth69/otakio/releases)).
2. No app, abra **Extensões** e aperte **Select** → **Adicionar repositório**.
3. Digite `Garryth69/otakio-extensions` e confirme.
4. Na aba **Disponíveis**, escolha o idioma com **Start** e instale as fontes com **X**.

O app procura atualizações deste repositório ao abrir: quando uma extensão muda de versão aqui, a aba
**Atualizações** do app avisa e atualiza com um clique.

> Enquanto este repositório estiver **privado**, o Vita não consegue baixá-lo (o GitHub exige login para conteúdo
> privado). Ele passa a funcionar no app quando for tornado público.

## Aviso legal

- **Nenhum conteúdo é hospedado aqui.** Cada extensão é um script que, no console do usuário, lê páginas públicas de
  um site de terceiros, como um navegador faria.
- Este projeto não tem afiliação com os sites listados, nem com editoras ou autores. Os nomes dos sites são usados
  apenas para identificar de onde a extensão lê.
- Nenhuma extensão contorna proteções anti-bot (Cloudflare etc.), paywalls ou logins. Sites que exigem isso ficam
  marcados como fora do ar.
- **Pedidos de remoção:** se você é responsável por um site ou obra e quer que a extensão correspondente seja
  removida, abra uma issue neste repositório. Ela será retirada.
- Apoie os autores: compre as edições oficiais e use os serviços oficiais.

## Resumo

{summary}

Status: **🟢 funciona** (lista, capítulos e páginas testados) · **🟡 parcial** (algo falha) · **🔴 fora do ar**
(o site não responde ou bloqueia leitores) · **⚪ não testada**. O status abaixo vem do último teste automático
(`health.json`); no Vita, a bolinha de cada fonte também se ajusta sozinha conforme o uso.

## Fontes
"""

FOOTER = """
## Estrutura do repositório

| Caminho | Conteúdo |
|---|---|
| `index.json` | catálogo lido pelo app (id, nome, idioma, versão, arquivo, status) |
| `extensions/` | as extensões publicadas, um `.lua` por fonte |
| `native/` | código-fonte das extensões nativas (sites com API ou layout próprio) |
| `health.json` | resultado do último teste automático de cada fonte |

### Formato do `index.json`

```json
{{
  "name": "Otakio Extensions", "format": 1, "minEngine": 1,
  "extensions": [
    {{"id": "otakio.mangapill", "name": "Mangapill", "lang": "en", "version": 1, "nsfw": false,
      "engine": "native", "baseUrl": "https://mangapill.com", "file": "extensions/otakio.mangapill.lua",
      "origin": "otakio", "compat": "full", "health": "ok", "checked": "2026-11-03"}}
  ]
}}
```

`file` é relativo ao `index.json` (ou `url`, absoluto). O app instala uma extensão de novo quando `version` aumenta.
Qualquer pessoa pode montar um repositório próprio nesse formato e adicioná-lo no app.

### Como as extensões são feitas

Extensões do Mihon/Tachiyomi são APKs Kotlin para Android e não rodam no Vita. O Otakio reimplementa em Lua os
**temas** que muitos sites compartilham (Madara, MangaThemesia, Keyoapp, ZeistManga, FoolSlide, MangaCatalog,
YiiManga, VineTheme, HeanCms, Guya, PizzaReader...). Para esses sites, a extensão é só uma configuração do tema.
Sites com estrutura própria têm extensões **nativas**, escritas à mão em `native/`.

O catálogo é gerado e testado pelas ferramentas do repositório do app
(`tools/gen_repo.py`, `tools/probe_sources.py`, `tools/gen_repo_readme.py`). Sites que fecharam de vez ficam fora do
catálogo (`CLOSED_SITES` em `tools/gen_repo.py`).

## Créditos

- **[keiyoushi/extensions-source](https://github.com/keiyoushi/extensions-source)** (Apache 2.0): a lógica dos
  temas e a lista de sites das extensões marcadas como "tema keiyoushi" foram adaptadas do código Kotlin deles.
- **[yuzono/tachiyomi-extensions](https://github.com/yuzono/tachiyomi-extensions)**,
  **[yuzono/cursed-manga-extensions](https://github.com/yuzono/cursed-manga-extensions)** e
  **[codegeasse1/codegeasse-mihon-extension](https://github.com/codegeasse1/codegeasse-mihon-extension)**:
  configurações de sites que usam os mesmos temas.
- **[Creckeryop/NOBORU-parsers](https://github.com/Creckeryop/NOBORU-parsers)**: os parsers clássicos do NOBORU
  ("parser NOBORU") são baixados direto do repositório original, sem cópia aqui.
- **Comunidade [Mihon](https://github.com/mihonapp/mihon)/Tachiyomi**, pelo modelo de extensões e repositórios.
- **Extensões nativas e adaptação para Lua:** Garryth69, com auxílio de IA (Claude, da Anthropic).

## Licença

[Apache 2.0](LICENSE). Veja [NOTICE.md](NOTICE.md) para as atribuições de código de terceiros.
"""


def main():
    index = json.load(open(os.path.join(REPO, "index.json"), encoding="utf-8"))
    exts = index["extensions"]
    by_lang = collections.defaultdict(list)
    for e in exts:
        by_lang[e["lang"]].append(e)
    ok = sum(1 for e in exts if e.get("health") == "ok")
    lines = ["| Idioma | Fontes | 🟢 funcionando |", "|---|---:|---:|"]
    for code, label in LANGS:
        items = by_lang.get(code, [])
        if items:
            lines.append(f"| {label} | {len(items)} | {sum(1 for e in items if e.get('health') == 'ok')} |")
    lines.append(f"| **Total** | **{len(exts)}** | **{ok}** |")
    out = [HEADER.format(summary="\n".join(lines))]
    for code, label in LANGS:
        items = by_lang.get(code, [])
        if not items:
            continue
        order = {"ok": 0, "partial": 1, "relay": 1, None: 2, "dead": 3}
        items.sort(key=lambda e: (order.get(e.get("health"), 2), e["name"].lower()))
        out.append(f"\n### {label} ({len(items)})\n")
        out.append("| Fonte | Site | Status | Tipo | +18 |")
        out.append("|---|---|---|---|:---:|")
        for e in items:
            host = e.get("baseUrl", "").replace("https://", "").replace("http://", "").rstrip("/")
            out.append(f"| {e['name'].replace('|', '/')} | {host} | {STATUS.get(e.get('health'), e.get('health'))} | "
                       f"{ORIGIN.get(e.get('origin'), e.get('origin'))} | {'sim' if e.get('nsfw') else ''} |")
    out.append(FOOTER.format())
    with open(os.path.join(REPO, "README.md"), "w", encoding="utf-8", newline="\n") as fh:
        fh.write("\n".join(out))
    print("repo/README.md:", len(exts), "extensions")


if __name__ == "__main__":
    main()
