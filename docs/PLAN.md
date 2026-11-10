# Lume: plano

## Decisões já tomadas

| Assunto | Decisão |
| --- | --- |
| Tela | 540 de largura, `expand_height`, aspecto de 9:22 a 4:5; fora disso, barras |
| Mundo | maior que a tela, câmera 2D (`setCamera`), y para baixo; fases de 2 a 4 telas de altura |
| Passo | simulação a 120 Hz fixos com acumulador; `Rng` própria com a semente da fase |
| Luz | mapa de luz numa textura (todas as fontes somadas), multiplicado sobre a cena; brilho aditivo por cima |
| Engine | o Diego liberou mexer no `pequi` no que o jogo precisar (10/11/2026); a lista está na "Fase 0.5" |
| Input | `Controls` único: guiar, pulsar (toque curto), apagar (2 dedos / botão direito / Espaço) |
| Fases | tabela em Zig (`levels.zig`): tamanho, objetos, N do cupinzeiro, estrelas, vento |
| Arte | Fase 1 toda em código (texturas geradas); silhuetas finais em SVG próprio, como no Safra |
| Som | Fase 1 com `synth`; ambiente e notas finais sintetizados em `tools/audio.py` |
| Desktop | Windows com janela; Linux só headless (lacuna 3) |

## Módulos

```
src/
  main.zig      App, memória, assets, áudio, telas, debug
  input.zig     pequi.Input -> Controls
  sim.zig       estado da fase e o passo fixo; eventos para a tela
  boids.zig     líder e enxame (separação, alinhamento, coesão, atraso)
  predators.zig sapo, aranha, coruja, lobo-guará
  levels.zig    as 12 fases
  light.zig     véu, furo, halos
  view.zig      câmera, paralaxe, desenho da fase, HUD
  screens.zig   título, mapa, pausa, vitória, derrota, configurações
  sfx.zig       notas, escala de resgates, acorde, ambiente
  progress.zig  fases liberadas e estrelas
  robot.zig     robô de debug que joga pelos Controls
```

A simulação não importa nada de render nem de áudio: devolve eventos
(resgatou, perdeu, pulsou, sapo inflou, acendeu) que a tela e o som leem.

## Fase 0.5: mudanças na engine

Só o que o Lume precisa, cada uma geral (serve a qualquer jogo), com teste
e README no `pequi`. Detalhes em `ENGINE_GAPS.md`.

| # | Mudança | Quando | Por quê |
| --- | --- | --- | --- |
| 1 | Render-to-texture (`beginTarget` / `endTarget`) | antes da Fase 1 | o mapa de luz: a luz é o jogo |
| 2 | Blend `.multiply` | antes da Fase 1 | aplicar o mapa de luz sobre a cena |
| 6 | Roteiro headless: segundo dedo, botão direito, teclas | antes da Fase 1 | jogar e verificar o apagar sem janela |
| 7 | `Input.pixels_per_dp` | Fase 2 | alvos de toque de 48dp de verdade |
| 4 | `PlatformApi.vibrate` | Fase 3 | haptics no pulso, na perda e na vitória |

Ficam de fora: janela no Linux (3, combinado com o Diego) e toques no
Win32 (5, o mouse resolve).

## Fase 1: fatia vertical (feita)

1. Esqueleto do repositório (build, CI, Android) e tela preta rodando.
2. Líder + boids em arrays fixos (200), com testes de contagem e determinismo.
3. Luz: céu, silhuetas de teste, mapa de luz multiplicado, halos aditivos.
4. Pulsar e apagar, com custo e ganho: o pulso chama perdidos e acorda o
   sapo; apagado, o sapo perde o rastro e o enxame anda devagar.
5. Perdidos piscando, um sapo com lagoa, um cupinzeiro com N; vitória,
   derrota e estrelas.
6. Um som por ação; robô de debug; roteiros de captura.
7. Ajuste de números até a escolha pulsar/apagar ter graça; medição do
   frame com 200 vaga-lumes.

**Feito quando:** `zig build`, `test`, `android`, `check-android` e
`check-render` passam; uma partida ganha e uma perdida de propósito (robô e
roteiro); relatório com tempos de frame.

## Fase 2: jogo completo (feita)

- 12 fases: Vereda 1-4 (sapos), Campo Sujo 5-8 (teias), Chapada 9-12
  (corujas, vento); a 1 é o tutorial por gestos, a 12 usa tudo; lobo-guará
  a partir da 6.
- Telas, progresso salvo, volumes, safe areas, alvos de 72 unidades.
- Ambiente por região, escala de resgates, acorde do cupinzeiro.
- Silhuetas próprias de cada região (buriti, canela-de-ema, pequizeiro),
  feitas em código; paralaxe de 4 camadas, vegetação balançando. Arte
  ilustrada ficou no `BACKLOG.md`.

## Fase 3: game feel (feita)

Cascata do cupinzeiro, hit-stop e rastro na perda, antecipação da coruja e
do sapo, câmera que antecipa e abre com o enxame. Tudo listado em
`docs/FEEL.md`. Haptics no Android, com a mudança 4 da engine.

## Riscos

| Risco | Como eu trato |
| --- | --- |
| Render-to-texture falhar em algum GPU | RGBA8 como alvo é garantido por GL 3.3 e GLES 3.0, e foi testado nos dois (headless e Android simulado); se mesmo assim falhar, a engine registra no log e pula o alvo, e a cena fica só em silhuetas |
| Haptics e dp só se confirmam em aparelho | eu testo no Android simulado; a confirmação final é sua no celular |
| Tempo de frame medido aqui é com GL por software | reporto o tempo de CPU do jogo (`debug.timed`); o número de GPU real vem do seu PC e do celular |
| "Divertido" não se mede por robô | o robô acha números quebrados; o julgamento final é seu no aparelho |
| Dois dedos para apagar pode atrapalhar o arrasto | o primeiro dedo continua guiando; se ficar ruim no aparelho, viro um botão na tela |
