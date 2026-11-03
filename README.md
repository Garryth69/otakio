# Otakio

**Leitor de mangá para PS Vita** — biblioteca, leitor, downloads offline, importação de arquivos `.cbz`/`.zip` e backup.
Fork do [NOBORU](https://github.com/Creckeryop/NOBORU), com recursos inspirados no [Mihon](https://github.com/mihonapp/mihon).

Interface em português, inglês, espanhol, francês, alemão e italiano.

> *English:* Otakio is a manga reader for the PS Vita (homebrew, fork of NOBORU). The app ships **without any content
> sources**. Sources are optional extensions installed from an extension repository the user adds. See
> [Extensions](#extensões) and [Legal notice](#aviso-legal).

---

## Aviso legal

- O Otakio é **apenas um leitor**. Ele **não hospeda, não distribui e não inclui** nenhum mangá, HQ ou imagem.
- O app **não vem com fontes/extensões**. Ele só mostra conteúdo de repositórios de extensões que **o próprio usuário
  escolhe adicionar**, do mesmo jeito que o Mihon/Tachiyomi.
- Este repositório não tem nenhuma afiliação com os sites, editoras ou autores das obras.
- Você é responsável pelo que acessa. Apoie os autores: compre as edições oficiais e use os serviços oficiais
  (MANGA Plus, Webtoons, Comics Kingdom, editoras locais etc.).

## Instalação

1. Baixe o `Otakio-x.y.vpk` da página [Releases](../../releases) e instale pelo **VitaShell** (o Vita precisa de
   HENkaku/Ensō).
2. Abra o Otakio. Na primeira vez a aba **Extensões** está vazia: o app não traz nenhuma fonte.
3. Adicione um repositório de extensões (veja abaixo) e instale as fontes que quiser.

Os seus dados ficam em `ux0:data/otakio/` e **não são apagados** quando você instala uma versão nova por cima.

## Extensões

As fontes são pequenos arquivos Lua publicados em um *repositório de extensões* (um `index.json` + arquivos
`.lua`). O repositório de extensões do projeto é o
**[Garryth69/otakio-extensions](https://github.com/Garryth69/otakio-extensions)**, mantido separado do app.

Para adicionar um repositório no Vita:

1. Vá em **Extensões** e aperte **Select** (ou Mais → Configurações → Extensões → Repositórios).
2. Escolha **Adicionar repositório** e digite só `usuario/repositorio`, por exemplo `Garryth69/otakio-extensions`.
   Também é aceito o endereço completo de qualquer `index.json`.
3. A aba **Disponíveis** passa a listar as fontes. **Start** troca o idioma; **X** instala.

Cada fonte tem uma bolinha de status: **verde** funciona, **amarela** está instável, **vermelha** não funciona. O
status se atualiza sozinho (as fontes instaladas são testadas ao abrir o app e conforme você lê). Quando o
repositório publica versões novas das extensões, a aba **Atualizações** avisa.

Repositórios no formato do Mihon (APKs Android) podem ser adicionados, mas as extensões deles não rodam no Vita: o
app só indica quantas daquelas fontes já têm equivalente em Lua.

## Atualizações do app

O Otakio consulta a última versão publicada em [Releases](../../releases) ao abrir (se houver internet) e avisa
quando existe uma versão nova. Em **Mais → Configurações → Sobre → Verificar atualização do app** você baixa o VPK
novo direto para `ux0:/vpk/`; depois é só instalar pelo VitaShell. Biblioteca e configurações são mantidas.

## Recursos

- Biblioteca com categorias, filtros e verificação de capítulos novos.
- Busca dentro de cada fonte (**Triângulo** no catálogo) e busca global.
- Downloads para ler offline; a aba **Downloads** mostra a fila e tudo que já foi baixado.
- Importação de arquivos próprios: copie `.cbz`, `.zip` ou pastas de imagens para `ux0:data/otakio/import/`.
- Backup e restauração (Mais → Dados): biblioteca, progresso, histórico, categorias, repositórios e extensões.
- Importação dos dados do NOBORU, se existir `ux0:data/noboru/`.
- Salvar a página atual como PNG, JPEG ou WebP.
- Motor com TLS 1.3 e WebP nativos.

## Problemas

`ux0:data/otakio/log.txt` registra o carregamento das extensões, as instalações e os erros. Anexe esse arquivo ao
abrir uma [issue](../../issues).

## Desenvolvimento

Estrutura:

| Pasta | Conteúdo |
|---|---|
| `source/` | o app (Lua) + `eboot.bin` (motor) + `sce_sys/` (ícone e LiveArea) |
| `engine/` | patches e script para recompilar o motor lpp-vita (ver `docs/ENGINE_REBUILD.md`) |
| `tools/` | gerador do VPK, gerador do catálogo de extensões, testador de fontes e simulador do Vita |
| `repo/` | **não faz parte deste repositório**: é o clone do repositório de extensões |

Comandos (Python 3 + `pip install lupa pillow`):

| Comando | O que faz |
|---|---|
| `python tools/build_vpk.py --name Otakio-1.0.vpk` | checa a sintaxe Lua e gera o VPK de lançamento (sem extensões) |
| `python tools/build_vpk.py --with-catalog` | VPK de teste com o catálogo de `source/repo/` embutido |
| `python tools/tests/sim.py <cenário> [--online] [--shots 100,200]` | roda o app inteiro num Vita simulado e tira screenshots |
| `python tools/run_lua.py tools/tests/test_core.lua` | testes de JSON, HTML e serialização |
| `python tools/gen_assets.py` | gera ícones, logo e LiveArea |

Para mexer nas extensões, clone o repositório de extensões dentro da pasta `repo/`:

```
git clone https://github.com/Garryth69/otakio-extensions repo
```

Depois:

| Comando | O que faz |
|---|---|
| `python tools/gen_repo.py --kei <dir> --noboru <dir> [...] [--probe]` | gera o catálogo `repo/` a partir dos temas do keiyoushi, dos parsers do NOBORU e das extensões nativas de `repo/native/` |
| `python tools/probe_sources.py [--ids arquivo]` | testa as fontes ao vivo e grava `repo/health.json` |
| `python tools/trace_source.py <id>` | mostra cada requisição HTTP que uma extensão faz |

### Publicar uma versão nova

1. Aumente `VERSION`/`VERSION_NAME` em `source/assets/libs/config.lua` e `APP_VER` em `tools/build_vpk.py`.
2. `python tools/build_vpk.py --name Otakio-X.Y.vpk`
3. Crie a release `vX.Y` com o VPK anexado:
   `gh release create vX.Y build/Otakio-X.Y.vpk --title "Otakio X.Y" --notes "..."`

O app compara a tag da release mais recente com a própria versão e oferece o download do `.vpk` anexado.

> Enquanto este repositório estiver **privado**, o Vita não consegue consultar as releases (a API do GitHub exige
> login para repositórios privados). A atualização automática passa a funcionar quando o repositório for público.

## Licença

**GPLv3** ([LICENSE](LICENSE)), a mesma do NOBORU, do qual o Otakio é um fork. Quem distribuir o VPK deve
disponibilizar também o código-fonte, incluindo as mudanças no motor em `engine/patches/`.

Os motores de tema em `source/assets/libs/engines.lua` e `engines_extra.lua` adaptam para Lua a lógica dos temas do
[keiyoushi/extensions-source](https://github.com/keiyoushi/extensions-source), distribuídos sob a
[Licença Apache 2.0](https://www.apache.org/licenses/LICENSE-2.0).

## Créditos

- **Autor:** Garryth69. O desenvolvimento foi feito com auxílio de IA, o Claude (Anthropic).
- **NOBORU**, de [Creckeryop](https://github.com/Creckeryop): leitor original e fork do motor.
- **Motor:** [lpp-vita](https://github.com/Rinnegatamante/lpp-vita) (Rinnegatamante), VitaSDK, vita2d (xerpi),
  LuaJIT, curl, OpenSSL, libpng, libjpeg e libwebp.
- **Temas de fontes:** comunidade [Mihon](https://github.com/mihonapp/mihon) e [keiyoushi](https://github.com/keiyoushi).
- **Traduções originais do NOBORU:** SamuEDL, theHeroGAC, Rinnegatamante, Samilop Iter, lukrynka e rutantan.
