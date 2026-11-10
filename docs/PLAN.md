# Lume: plano

## Decisões já tomadas

| Assunto | Decisão |
| --- | --- |
| Tela | 540 de largura, `expand_height`, aspecto de 9:22 a 4:5; fora disso, barras |
| Mundo | maior que a tela, câmera 2D (`setCamera`), y para baixo; fases de 2 a 4 telas de altura |
| Passo | simulação a 120 Hz fixos com acumulador; `Rng` própria com a semente da fase |
| Luz | véu preto com um furo no enxame + brilho aditivo (sem render-to-texture) |
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

## Fase 1: fatia vertical

1. Esqueleto do repositório (build, CI, Android) e tela preta rodando.
2. Líder + boids em arrays fixos (200), com testes de contagem e determinismo.
3. Luz: céu, silhuetas de teste, véu com furo, halos aditivos.
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

## Fase 2: jogo completo

- 12 fases: Vereda 1-4 (sapos), Campo Sujo 5-8 (teias), Chapada 9-12
  (corujas, vento); a 1 é o tutorial por gestos, a 12 usa tudo; lobo-guará
  a partir da 6.
- Telas, progresso salvo, volumes, safe areas, alvos de 72 unidades.
- Ambiente por região, escala de resgates, acorde do cupinzeiro.
- Arte final em silhuetas, paralaxe de 4 camadas, vegetação balançando.

## Fase 3: game feel

Cascata do cupinzeiro, hit-stop e rastro na perda, antecipação da coruja e
do sapo, câmera que antecipa e abre com o enxame. Tudo listado em
`docs/FEEL.md`. Haptics fica de fora (lacuna 4).

## Riscos

| Risco | Como eu trato |
| --- | --- |
| Um furo só no véu pode parecer pobre | testar cedo na Fase 1; se não convencer, eu paro e proponho render-to-texture na engine |
| Tempo de frame medido aqui é com GL por software | reporto o tempo de CPU do jogo (`debug.timed`); o número de GPU real vem do seu PC e do celular |
| "Divertido" não se mede por robô | o robô acha números quebrados; o julgamento final é seu no aparelho |
| Dois dedos para apagar pode atrapalhar o arrasto | o primeiro dedo continua guiando; se ficar ruim no aparelho, viro um botão na tela |
