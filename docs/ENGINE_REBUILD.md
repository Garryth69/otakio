# Recompilação do motor (lpp-vita) — progresso

Objetivo: novo `eboot.bin` com TLS 1.3 (MangaDex etc. sem relay), WebP nativo e decodificador de GIF seguro.

## Ambiente encontrado
- WSL2 Ubuntu-24.04, VitaSDK em `/usr/local/vitasdk` (gcc 10.3, build 2025-03-11).
- SDK traz curl 8.17.0, mas OpenSSL 1.0.2i (só TLS 1.2) → precisa de TLS moderno (mbedTLS 3.6 ou OpenSSL 3).
- Faltam no Ubuntu: autoconf, libtool.

## Código do motor
- Fork do NOBORU: https://github.com/Creckeryop/lpp-vita, branch `master` (0ab66ae, 2022-01-08) — tem todas as funções usadas pelo Otakio.
- Clonado em `~/otakio-engine/lpp-vita` (dentro do WSL).

## Etapas
- [x] 1. Achar fonte do motor e toolchain
- [x] 2. Compilar o motor original (OK em 2026-11-02 → `~/otakio-engine/lpp-vita/eboot_unsafe.bin`)
  - libvita2d do fork: https://github.com/Creckeryop/libvita2d → `~/otakio-engine/libvita2d/libvita2d` (make)
  - vdpm: libsndfile speexdsp mpg123 opus opusfile luajit libwebp mbedtls lame flac libvorbis bzip2 zstd
  - Makefile: -lluajit-5.1, include luajit-2.1 e opus, -D_GNU_SOURCE -include string.h, sem -ldl,
    + -lFLAC -lmp3lame -lvorbisenc -lvorbis -logg, -lbz2, -lzstd -lz; libvita2d do fork via V2D_DIR
  - fontes: `#include <cstring>` em videodec.cpp; luaL_setfuncs só p/ LuaJIT < 2.1; `source/include/dl_stubs.c`
- [x] 3. TLS 1.3: vdpm openssl-1.1.1 (1.1.1t) + curl 8.17 recompilado da receita vitasdk/packages contra ele
  (o libcurl.a do vdpm ainda era 1.0.2). Stub `source/include/ssl_stubs.c` (UI_OpenSSL -> UI_null), -lpthread.
  Motores salvos em `otakio/engine/`: eboot_base.bin (sem TLS 1.3) e eboot_tls13.bin.
  Lua: `Relay.nativeTls13` (jit.version_num >= 20100) desliga o relay; log.txt registra "engine: ...".
  VPKs: build/Otakio-motor-novo.vpk e build/Otakio-motor-base.vpk (`build_vpk.py --eboot ... --name ...`).
- [ ] 4. Teste no Vita: MangaDex sem relay  ← AGUARDANDO TESTE DO USUÁRIO
- [ ] 5. WebP nativo (libwebp) + GIF seguro
- [ ] 6. Teste no Vita

## Notas
- Teste 1 (eboot_tls13.bin): crash ao abrir, antes do Lua logar. psp2core: lua_loadimg → load_PNG_file_downscaled
  → png_read_info → read_png_fn → PC no endereço NÃO relocado do stub sceIoRead (0x814E5B70+4/+8) em 2 dumps
  com bases diferentes. Imports/NIDs iguais aos do motor antigo. vita-elf-create sem avisos.
- Teste 2: eboot_tls13_nosibling.bin (-fno-optimize-sibling-calls) trocado direto em ux0:app/OTAK00001/eboot.bin
  via FTP (com backup do eboot instalado).
  Próximo diagnóstico se falhar: testar eboot_base.bin (SDK novo sem TLS) para separar SDK x OpenSSL.
- Teste 2 OK: app abre, API do MangaDex OK. Problemas: Importar (erro Lua) e imagens do MangaDex.
  - Causa 1: motor do NOBORU era build release → `-DSKIP_ERROR_HANDLING` (checagens de argc desligadas).
  - Causa 2: luaNetwork.cpp forçava header "User-Agent: Chrome 58" (sobrescrevia CURLOPT_USERAGENT) e
    o MangaDex devolve página HTML de bloqueio p/ UA de navegador. Patch: sem UA fixo, Content-Type/Length
    só em POST, SCE_O_TRUNC no download. Lua: net.lua userAgentFor() usa "Otakio/<versão>" p/ mangadex.
  - Motor agora é o padrão em source/eboot.bin; patch do lpp em engine/patches/. Versão 1.0.5-test.
- Dumps/log lidos por FTP: VitaShell <IP do Vita>:1337 (sem NLST; usar CWD + LIST).
- 1.0.6-test (UI): fontes maiores (13→15, 16→18, 20→22, 26→28, 30→32, em globals.lua), cache de Font.getTextWidth,
  barra de dicas com FONT13, chips 30px, linhas de 2 níveis no Dialog, seletor de idioma virou Dialog.choice
  (cenário `sim.py lang`). MangaDex ainda não funciona no Vita (usuário, 2026-11-02): investigar depois da UI.
- 1.0.7-test: MangaDex no Vita do usuário era `noboru.mangadex` (API v2 morta, Disabled=true). Removidos
  noboru.mangadex/mangadexdif do repo; extensions.lua troca automaticamente pelo otakio.mangadex (REPLACED_BY).
  sim.py agora emula o motor novo (TLS 1.3 + UA do Lua; `--tls12` = motor antigo): MangaDex nativo OK (capas+páginas).
  UI: fontes 20/24/30/34 (rail 15), tema padrão roxo escuro + ícone/LiveArea roxos, repetição de botões 260ms, rolagem mais rápida.
- 1.0.8-test: Vita ainda sem MangaDex após troca p/ otakio.mangadex (log confirmou a troca). Adicionado autodiagnóstico
  (Extensions.diagnoseMangaDex, roda ao abrir em builds "-test"): grava no log.txt lista/capa/at-home/página com bytes,
  hex e resolução. "image failed: <url>" também vai para o log. Dados do usuário (ux0:data/otakio) apagados a pedido.
  PRÓXIMO: ler ux0:data/otakio/log.txt após o usuário abrir o app (linhas "diag ...").
  Forks NOBORU: ChaviAlmeida (MangaDex3 v5, apagado), Golden-dreamer (MangaDex2 v5 + Accept-Encoding: identity; motor
  modificado com proxy) — nenhum truque além de API v5 + TLS 1.3/proxy.
- 1.0.9-test: MangaDex abandonado a pedido do usuário. Log do Vita mostrou JSON grande (147 KB) decodificando vazio no
  console (causa ainda desconhecida) → autoteste Extensions.selfTest (Flame browse.json + capa WebP) grava erro exato.
  Motor: WebP nativo (source/include/webp_pic.c, -lwebp; piclib detecta RIFF/WEBP; getImageFormat "webp").
  Lua: ImageProxy.nativeWebp (probe app0:assets/images/probe.webp) → WebP sem wsrv (wsrv bloqueia flamecomics).
  Flame v2: capas via /_next/image?w=384 (42 KB em vez de 3,9 MB). Primeira execução sem extensões (sem STARTER).
  PRÓXIMO: ler linhas "selftest" no log.txt do Vita.
- 1.0.10-test: CAUSA do JSON quebrado no Vita: NetString do luaNetwork.cpp conta o NUL final (length começa em 1)
  → toda resposta de texto vinha com 1 byte a mais; o Json.decode rejeitava "trailing data". Corrigido no motor
  (asyncResSize = length - 1) e no Lua (net.lua remove NUL final; json.lua ignora NUL). sim.py agora anexa NUL.
  Motor: TLS mínimo 1.0 (negocia até 1.3 por site). Indicadores verde/amarelo/vermelho: sourcestatus.lua
  (resultado no Vita > teste do PC). probe_sources.py: TLS 1.3, baixa 1ª página e checa formato; NOBORU clássicos
  sem teste (harness não tem Threads). Resultado: 166 ok, 41 parcial, 67 mortas (~44 Cloudflare), 37 sem teste.
- 1.0.11-test: usuário confirmou Flame Comics e MangaDex funcionando no Vita (fix do NUL). Teste com extensões
  Android originais (Suwayomi-Server v2.4.2366 em _ref/suwayomi; keiyoushi agora publica index.pb, não index.min.json):
  49 fontes funcionavam no Android e não no Otakio → 38 com imagem real. Correções genéricas: Madara div.wp-manga-chapter,
  API /api/comics/<slug>/chapters (KunManga/ZinManga), canvas[data-page-url], imagens soltas no .reading-content,
  cfg.archiveSelector; Zeist textarea#zeist-raw-data e wz_pages_chapter. gen_repo lê archiveSelector/archiveUrlSelector/
  chapterListSelector/pageListParseSelector do Madara novo. Resultado: 174 verdes. NÃO contornar anti-bot/hotlink.
  PENDENTE: suporte a repo Mihon v2 (index.pb protobuf) no Otakio; ports custom (Keyoapp x-data, mhscans Astro, etc.).
- 1.0 (versão pública, 2026-11-02): removidos GIF animado, Changes, relay TLS (código, ajuste, tools/relay), CheckUpdate,
  doadores, ParserChecker, autoteste, modo "Sempre" do proxy de imagem. Proxy em um item (Dialog), Importar NOBORU
  só com ux0:data/noboru, menu do leitor virou Dialog (extra.lua), tela Sobre com cartão de créditos.
  Idiomas: um arquivo por idioma (lang_en/pt/es/fr/de/it.lua), language.lua faz fallback p/ inglês; os outros 8
  idiomas do NOBORU saíram. Triângulo no catálogo = busca na fonte. Downloads mostra mangás baixados (Quadrado apaga).
  Aba Multi removida: fontes "all" aparecem em todo idioma; chips FR/DE/IT. Motor PizzaReader (+7 fontes fr/it),
  12 fontes fr/it novas ok, Webtoons FR/DE. SourceStatus: histórico dos 6 últimos resultados + checagem em segundo
  plano de todas as fontes instaladas ao abrir o app (depois a cada 6 h). Backup: histórico agora é restaurado;
  cenários sim.py backup/restore. Dados pessoais removidos (IP do Vita, caminhos locais).
- 1.0 (motor): System.convertImage(src, dst, "jpg"|"png"|"webp"[, q]) em engine/patches/imgconv.c (libjpeg, libpng,
  libwebp com encoder; decodifica em RAM, resolução total) + patch_convertimage.py; build: engine/build_convert.sh (WSL,
  acrescenta -lsharpyuv). Motor anterior: engine/eboot_before_convert.bin. "Salvar imagem" converte para o formato de
  Mais > Leitor > Formato ao salvar imagem: PNG (padrão), JPEG ou WebP; se a conversão falhar, mantém o original.
  Atenção: main.lua restringe System (sandbox) depois de carregar as libs — capture funções do System no load.
- 1.0: removido Mais > Dados > Capítulos baixados (AdvancedChaptersDeletion), redundante com a aba Downloads.
