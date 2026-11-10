# Pequi: o que o Lume usa

Notas da leitura do `pequi`, atualizadas para `252ae7b` (API de plataforma
versão 13, Zig 0.17.0), que já tem as mudanças pedidas pelo Lume. Tudo que o jogo fizer precisa bater com este arquivo; se a engine
mudar, ele muda junto.

## 1. As quatro perguntas

| Recurso | Há? | Onde | Consequência para o Lume |
| --- | --- | --- | --- |
| Blending aditivo | **Sim** | `pequi.render.setBlend(render, .additive)` (GL: `SRC_ALPHA, ONE`) | brilho, bloom falso e partículas de luz |
| Render-to-texture | **Sim, desde `00d72eb`** | `render.beginTarget(render, texture)` / `endTarget(render)`; não havia na primeira leitura (lacuna 1) | mapa de luz e textura das cores iluminadas (seção 6) |
| Multitouch | **Sim, no Android** | `input.touches: [10]Touch` com `id`, `x`, `y`, `down`, `pressed`, `released` | dois dedos = apagar. No Win32 `touches` fica vazio (só mouse); lacuna 5 |
| Vários sons com pitch | **Sim** | `Mixer`: 64 vozes, `PlayOptions.pitch`, `setPitch`, `setVolume` com rampa | escala de resgates com um som só; ambiente em camadas |

O blend `.multiply` entrou junto, e depois a densidade da tela
(`input.pixels_per_dp`). Ainda não há: haptics, janela no Linux, teclas
além das mapeadas. Ver `ENGINE_GAPS.md`.

## 2. Fronteira engine/jogo

O jogo é uma biblioteca dinâmica (`lume_game`) que a plataforma carrega e
pode recarregar a quente. O arquivo raiz declara:

```zig
const pequi = @import("pequi");
comptime { pequi.exportGame(@This()); }
pub const panic = pequi.panic;

pub fn updateAndRender(memory: *pequi.GameMemory, input: *pequi.Input, render: *pequi.RenderCommands) void
pub fn getSoundSamples(memory: *pequi.GameMemory, buffer: *pequi.SoundBuffer) void
```

**Ciclo do frame** (plataforma):
1. junta o input e zera o buffer de render (`beginFrame`: blend `.alpha`,
   transformação de tela);
2. chama `updateAndRender` (simular e emitir comandos de desenho);
3. chama `getSoundSamples` (rápido: só `mixer.mix(buffer)`);
4. executa os comandos no GL e troca os buffers.

**`GameMemory`**
- `game_state: ?*anyopaque`: nulo no primeiro frame; o jogo guarda aqui o
  ponteiro do seu estado.
- `platform: PlatformApi`: também em `pequi.platformApi()` durante o frame.
- `display: pequi.display.Settings`: a tela virtual pedida (seção 4).
- `gpu_resources_lost: bool`: o Android perdeu o contexto GL; reenviar todas
  as texturas (as da engine voltam sozinhas).
- `reloaded: bool`: primeiro frame depois de um hot reload.

## 3. Memória

- `pequi.Arena` (`core/memory.zig`): `push(T)`, `create(T, v)`,
  `pushArray(T, n)`, `pushCopy`, `pushBytes`, `beginTemp()` / `Temp.end()`,
  `clear()`, `usedBytes()`. Memória entregue **zerada**. Blocos vêm de
  `memory.platform.block_allocator` (1 MB no mínimo por bloco).
- Estado do jogo: `pequi.memory.bootstrap(App, "arena", &memory.platform.block_allocator)`
  cria o `App` dentro da própria arena.
- **Hot reload:** nada de ponteiros para funções, vtables, literais de
  string ou `std.mem.Allocator` guardados no estado. Convenção do Cerrado e
  do Safra: `layout_size = @sizeOf(App)` no estado; se mudar depois de um
  reload, `mixer.stopAll()`, `arena.clear()` e começa de novo.
- **Regra do Lume:** o `App` e a simulação são structs de tamanho fixo
  (arrays com contador) criados uma vez na arena. O frame não aloca; o que
  for temporário usa `beginTemp`/`end`.

## 4. Tela, coordenadas e tempo

- O jogo desenha numa **resolução virtual**: origem no canto superior
  esquerdo, x para a direita, **y para baixo**, unidades = pixels virtuais.
  O tamanho deste frame está em `render.width` / `render.height`.
- `memory.display = .{ .width, .height, .scaling, .min_aspect, .max_aspect, .fullscreen }`.
  `.expand_height` mantém a largura e deixa a altura seguir a janela entre
  os dois aspectos; fora deles, barras. Lume: 540 de largura, retrato.
- `input.safe_area: Insets { left, top, right, bottom }` em unidades
  virtuais. `input.window_width/height` em pixels reais.
- `input.pixels_per_dp` e `input.dpToVirtual(48, render.width)`: o tamanho
  de um alvo de toque de 48dp em unidades virtuais, nesta tela. O Lume usa
  isso em `ui.touchSize` (entre 60 e 96 unidades).
- Câmera: `render.setCamera(render, cx, cy, zoom)` (um mundo com y para
  baixo; `zoom` = pixels virtuais por unidade), `setScreenSpace`,
  `setTransform([16]f32)`. Trocar de transformação fecha o lote atual.
- **Tempo:** `input.dt` é fixo por frame e igual a `1 / taxa do monitor`
  (60, 90, 120, 144...), não o tempo medido. `input.last_frame_seconds` é o
  tempo real do frame anterior (só para estatística). Como `dt` muda de
  aparelho para aparelho, **a simulação do Lume anda em passos fixos de
  1/120 s** com acumulador; os testes chamam o passo direto.

## 5. Input

```zig
input.mouse.x, .y            // unidades virtuais; .inside
input.mouse.button(.left | .middle | .right)   // ButtonState
input.touches[0..10]         // Touch { id, x, y, down, pressed, released }
input.controllers[0]         // teclado; 1..4 gamepads
    .button(.move_up/.move_down/.move_left/.move_right/
            .action_up/.action_down/.action_left/.action_right/
            .left_shoulder/.right_shoulder/.back/.start)
ButtonState: wasPressed(), wasReleased(), isDown()
input.debug_toggle           // F1 ou `; três dedos no Android
input.quit_requested = true  // pedir para fechar
```

- No Android o primeiro dedo também move o mouse (posição e botão
  esquerdo). No Win32 só há mouse; `touches` fica vazio.
- Teclado (Win32): WASD/setas, `Espaço` e `K` = `.action_down`, `Esc` =
  `.back` (o Voltar do Android também), `Enter` = `.start`. Não há teclas
  cruas nem roda do mouse.
- **Abstração do jogo** (`src/input.zig`): um `Controls { pointer_x,
  pointer_y, guiding, pulse, dark, back }` montado uma vez por frame.
  - guiar: botão esquerdo ou um dedo em baixo;
  - pulsar: soltar em menos de ~0,2 s e sem arrastar;
  - apagar: dois dedos em baixo, botão direito ou `.action_down`.
  A simulação só vê `Controls`, nunca `pequi.Input`.

## 6. Render

API em `pequi.render` (comandos acumulados; a plataforma desenha depois):

```zig
clear(render, r, g, b)
rect(render, x0, y0, x1, y1, rgba)
rectOutline(render, x0, y0, x1, y1, thickness, rgba)
sprite(render, texture, x0, y0, x1, y1, uv: UvRect, tint)
spriteRotated(render, texture, cx, cy, w, h, angle, uv, tint)   // radianos, horário
setBlend(render, .alpha | .additive | .multiply)
beginTarget(render, texture) / endTarget(render)   // desenhar numa textura
color(r, g, b, a) u32 / rgb(r, g, b)      // RGBA8, vermelho no byte baixo
text(render, x, y, size, bytes, rgba)     // fonte 8x8 embutida
textFont(render, font, x, y, scale, bytes, rgba) / textFontWidth(font, scale, bytes)
Textures.create(w, h) Texture             // manter um `Textures` no estado
uploadTexture(render, texture, pixels: []const u32, filter) bool   // .nearest/.linear/.mipmapped
```

- Uma cor só por quad (`tint` multiplica a textura); não há cor por vértice
  na API pública. Gradientes são texturas.
- Lotes: quads seguidos com a mesma textura, transformação e blend viram
  uma chamada de desenho. Limites por frame: 65 536 quads, 32 MB de upload
  de textura (`uploadTexture` devolve `false` e tenta-se no frame seguinte).
- Texturas podem ser **geradas em código** e enviadas com `uploadTexture`:
  é assim que a Fase 1 faz o ponto de brilho, o furo do véu e o gradiente
  do céu, sem arquivo de arte.
- `pequi.juice`: `Ease`, `tween`, `lerp`, `lerpColor`, `fade`, `approach`
  (meia-vida), `Spring`, `Shake`, `Particles(N)` (pool fixo; `emit`,
  `update(dt)`, `draw(render, tex, uvs, blend, dx, dy)`), `Rng` (só para
  efeitos; a simulação tem a própria semente).
- `pequi.ui`: menus (`begin`, `label`, `button`, `toggle`, `slider`, `end`,
  `Theme`), por toque, mouse, teclado e gamepad. Serve às configurações.
- `pequi.debug`: `timed("nome")` / `.end()`, `drawOverlay`; ligado em Debug
  e ReleaseSafe (`pequi.internal`).

**Desenhar em textura.** Entre `beginTarget` e `endTarget` o desenho 2D
vai para a textura (uma vaga de `Textures.create`, de qualquer tamanho,
nunca enviada com `uploadTexture`). O alvo representa a tela inteira: as
transformações valem como na tela, então um alvo pequeno desenhado com a
câmera da cena e depois esticado sobre a tela casa com ela. `clear` limpa o
alvo. Alvos não se aninham, não recebem cenas 3D e não podem ser desenhados
em si mesmos. Depois de `gpu_resources_lost` é só desenhar de novo.

**A luz do Lume**, todo frame:
1. céu e silhuetas de tudo, direto na tela;
2. **mapa de luz** (alvo de 135x300): limpo em preto, e cada luz somada em
   aditivo (o enxame, cada vaga-lume, o pulso, os perdidos, o cupinzeiro);
3. **cores** (alvo de 540x1200): a cena com as cores que a luz revela, e
   por cima o mapa de luz em `.multiply`; fica colorido só onde há luz;
4. as cores somadas (aditivo) sobre as silhuetas da tela;
5. o que brilha sozinho (vaga-lumes, olhos do sapo, larvas, partículas),
   as folhas escuras do primeiro plano e o HUD.

Não há blend "máximo": muitos halos no mesmo ponto estouram para branco,
então o halo de cada vaga-lume enfraquece conforme o enxame cresce.

## 7. Áudio

```zig
mixer: pequi.audio.Mixer            // no estado do jogo; 64 vozes; saída 48 kHz estéreo
mixer.play(&sound, .{ .bus, .volume, .pan, .pitch, .looping, .fade_in }) Handle
mixer.stop(h, fade) / stopAll() / setVolume(h, volume, pan, fade) / setPitch(h, pitch)
mixer.isPlaying(h) / playingCount() / mix(buffer)
pequi.audio.Volumes { master, music, effects }: load(api), apply(&mixer), save(api)
pequi.audio.synth: tone(arena, rate, Note) Sound; addNote(buf, rate, t, Note); toSound; pitch(semitons)
pequi.audio.Stream: pack.openStream(arena, nome); play(api, mixer, opts, loop); update(api, mixer) todo frame
```

- Dois barramentos: `.effects` e `.music`. O ambiente (grilos, sapos,
  vento) vai no `.music` como sons em loop, com `setVolume` por região.
- `pitch` é velocidade de leitura (2 = oitava acima): uma nota gravada vira
  a escala inteira com `synth.pitch`-style razões `2^(n/12)`.
- `Sound.samples` precisa viver enquanto toca (arena do jogo).
- Fase 1: todos os sons feitos em código com `synth` na inicialização.

## 8. Assets e progresso

- Pacote `.pqa` montado no build por `pequi-pack` a partir de
  `data/manifest.txt`:
  ```
  bitmap <nome> <png|tga|bmp> [nearest|linear|mipmap] [repeat]
  sound  <nome> <wav|ogg> [mono] [rate=<hz>] [stream]
  font   <nome> <ttf> <altura em px>
  ```
  Imagens viram RGBA8, sons PCM 16-bit (ou QOA com `stream`), fontes um
  atlas Latin-1.
- `Pack.open(arena, api, "lume.pqa")`, `loadBitmap(api, scratch, render,
  &textures, nome)`, `loadSound(api, arena, nome)`, `loadFont(...)`,
  `openStream(arena, nome)`. `error.NoRoomThisFrame` = tentar no próximo
  frame (carregamento em etapas, como no Safra).
- Progresso: `pequi.save.write(api, "progress", versao, &valor)` e
  `read(api, "progress", versao, T)`; `T` é `extern struct` sem ponteiros,
  até 64 KB. Erros: `NotFound`, `Corrupt`, `WrongVersion`, `WriteFailed`.
  Escrita atômica; salvar em menus e fim de fase, nunca todo frame.

## 9. Build e verificação

`build.zig` do jogo, igual ao do Safra (`pequi` clonado ao lado,
`.pequi = .{ .path = "../pequi" }`):

```zig
const game = pequi.addGame(b, pequi_dep, .{ .name = "lume", .root_source_file, .target,
    .optimize, .product_name = "Lume", .version, .window_size = .{ 540, 960 } });
pequi.addAssetPack(b, pequi_dep, game, b.path("data/manifest.txt"), "lume");
pequi.addAndroid(b, pequi_dep, game, .{ .library_name = "lume", ... }, android_step);
pequi.addAndroidCheck(b, pequi_dep, android, check_android, .{});
pequi.addRenderCheckIn(b, game, check_render, frames, "720x1280");
pequi.addScriptedRun(b, game, shots, script, frames, "720x1280", "shots/<nome>");
```

| Comando | O que faz | Onde roda |
| --- | --- | --- |
| `zig build -Dtarget=x86_64-windows` | executável e biblioteca do jogo | qualquer sistema |
| `zig build run` | o jogo com janela | só Windows |
| `zig build test` | testes do jogo (simulação sem janela) | host |
| `zig build android` | bibliotecas e assets para o Gradle em `android/` | qualquer sistema |
| `zig build check-android` | a biblioteca Android num ciclo de vida simulado | Linux x86_64 + Mesa |
| `zig build check-render` | renderiza sem janela em GL 3.3 e GLES 3.0 | Linux + Mesa |
| `zig build shots` | roteiros de toque e botões com capturas | Linux + Mesa |

- Roteiro da headless (`--input`): `tap`, `drag`, `finger2 F x y N` (segundo
  dedo), `right F N` (botão direito), `hold F <botão> N` (por exemplo
  `action_down`, o Espaço), `back`, `shot`. O primeiro dedo também aparece
  em `input.touches`, como no Android.
- O APK sai do CI (este ambiente não alcança o Android SDK).

## 10. Convenções herdadas do Cerrado e do Safra

- `src/main.zig`: `App` (arena, mixer, pacote, texturas, fontes, telas),
  carregamento em etapas, tratamento de `gpu_resources_lost`, overlay de
  debug com `input.debug_toggle`.
- Regras puras em módulos sem desenho, testadas por `zig build test`; a
  tela lê eventos das regras para animar e tocar sons.
- Assets gerados por scripts em `tools/`, já commitados em `data/`.
- Código e comentários em inglês; README e docs em português.
- `android/`: projeto Gradle copiado do Safra, só retrato.
- CI: formatação, testes, Windows, `check-render`, `check-android`, APK;
  precisa do secret `PEQUI_TOKEN`.
