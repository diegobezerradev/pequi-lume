# Lacunas do Pequi encontradas pelo Lume

Cada lacuna diz o que falta, por que importa, a API mínima proposta, o
esforço estimado e o contorno do lado do jogo. Nenhuma bloqueia o jogo; a
3 deixa uma plataforma do pedido de fora.

**Decisão (10/11/2026):** o Diego liberou mudar o `pequi` no que o jogo
precisar. Entram na engine as lacunas 1, 2, 6, 7 e 4 (nessa ordem, ver
`PLAN.md`); a 3 e a 5 ficam como estão. Quando uma lacuna for fechada,
ela ganha aqui a linha "Fechada em `<commit>`" e o `ENGINE_NOTES.md` é
atualizado.

| # | Lacuna | Bloqueia? | Contorno |
| --- | --- | --- | --- |
| 1 | Render-to-texture | não | véu preto com um furo + brilho aditivo |
| 2 | Blend multiplicar / máximo | não | o mesmo véu |
| 3 | Janela no Linux | **sem contorno** | Linux só headless; desktop = Windows |
| 4 | Haptics | não | nenhum (a Fase 3 pede "se a engine expuser") |
| 5 | Toques no Win32 | não | mouse; botão direito e Espaço para apagar |
| 6 | Roteiro headless só com um dedo | não | robô de debug no jogo + testes da simulação |
| 7 | Densidade da tela (dp) | não | alvo de toque fixo em unidades virtuais |

## 1. Render-to-texture

- **Falta:** desenhar numa textura e usá-la depois. O backend só tem o
  framebuffer do mapa de sombras 3D, interno.
- **Por quê:** a máscara clássica de luz (várias luzes somadas num mapa,
  multiplicado sobre a cena) e bloom de verdade.
- **API mínima:** `render.beginTarget(texture)` / `render.endTarget()` como
  entradas novas do buffer de comandos, com `Textures.createTarget(w, h)`.
- **Esforço:** 1 a 2 dias (comandos, `draw`, `gl` em GL 3.3 e GLES 3.0,
  recriação após perda de contexto, teste no headless). Muda `api_version`.
- **Contorno:** um véu preto com furo radial centrado no enxame (ver
  `ENGINE_NOTES.md`, seção 6). Custo: só uma luz revela o cenário; as
  outras só brilham.

## 2. Modos de blend

- **Falta:** só há `.alpha` e `.additive`.
- **Por quê:** com `multiply` (`DST_COLOR, ZERO`) e a lacuna 1 fechada, o
  mapa de luz escurece a cena direito; `max` evitaria estourar o brilho de
  200 halos sobrepostos.
- **API mínima:** mais valores em `render.Blend`.
- **Esforço:** 1 a 2 horas. Muda `api_version`.
- **Contorno:** halos com alfa baixo, para a soma não estourar.

## 3. Janela no Linux

- **Falta:** a plataforma com janela é só Win32; no Linux há a headless.
- **Por quê:** o pedido lista "Windows/Linux desktop".
- **API mínima:** nenhuma para o jogo: uma plataforma `linux` (X11 ou
  Wayland + EGL, ALSA ou PipeWire, evdev para gamepad).
- **Esforço:** 1 a 2 semanas para ficar no nível da Win32.
- **Contorno:** não há do lado do jogo. O Lume roda no Linux sem janela
  (testes, `check-render`, `shots`), que é como eu jogo e verifico aqui.

## 4. Haptics

- **Falta:** nada na `PlatformApi` vibra o aparelho.
- **API mínima:** `PlatformApi.vibrate(milliseconds: u32, strength: f32)`,
  sem efeito no PC.
- **Esforço:** meio dia (JNI para `Vibrator` / `VibrationEffect` e a
  permissão `VIBRATE` no manifesto).
- **Contorno:** nenhum; o item de haptics da Fase 3 fica de fora.

## 5. Toques no Win32

- **Falta:** `input.touches` só é preenchido no Android.
- **API mínima:** tratar `WM_POINTER` na Win32.
- **Esforço:** meio dia.
- **Contorno:** o que o pedido já prevê: toque emulado com o mouse, apagar
  no botão direito ou no Espaço.

## 6. Roteiro headless

- **Falta:** `--input` só tem `tap`, `drag`, `back` e `shot`: um dedo, sem
  botão direito, sem teclas.
- **Por quê:** não dá para roteirizar o APAGAR numa partida sem janela.
- **API mínima:** comandos `hold2 F N` (segundo dedo por N frames) e
  `key F <botão> N`.
- **Esforço:** 2 a 3 horas.
- **Contorno:** em builds de debug, um robô dentro do jogo dirige a mesma
  abstração de controles (como o robô do Safra), e os testes cobrem o
  apagar direto na simulação.

## 7. Densidade da tela

- **Falta:** o `Input` traz a janela em pixels, não em dp.
- **Por quê:** "alvos de toque ≥ 48dp".
- **API mínima:** `Input.pixels_per_dp: f32`.
- **Esforço:** 1 a 2 horas (Android: `AConfiguration_getDensity`; Win32: o
  DPI do monitor).
- **Contorno:** com 540 unidades de largura, o pior caso comum é um
  celular de 360dp (1dp = 1,5 unidade), então todo alvo tem pelo menos 72
  unidades. Em tablets fica maior do que precisa.
