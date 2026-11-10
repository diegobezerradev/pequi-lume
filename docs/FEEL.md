# Lume: game feel

Cada elemento de sensação do jogo, o que faz e onde está no código. Os
números estão em `src/game.zig` (tela) e em `sim.tune` (regras).

## O pedido da Fase 3

| Elemento | O que acontece | Onde |
| --- | --- | --- |
| Cascata do cupinzeiro | 44 larvas acendem da base ao topo em 2,6 s, cada uma crescendo com easing `out_back` e soltando faíscas; a luz do cupinzeiro abre com `in_out_cubic` e revela o cenário em volta | `cascade`, `moundLight`, `drawShining` |
| Acorde | uma nota a cada 5 larvas, 8 notas subindo, junto com a luz; no topo, um estouro de faíscas | `cascade`, `Sounds.chordNote` |
| Hit-stop | 70 ms de simulação parada quando um predador pega um vaga-lume | `hit_stop` em `update` e `react` |
| Flash | clarão avermelhado na tela, que some em 0,3 s | `flash` |
| Rastro do vaga-lume perdido | a luz dele é puxada até o predador (língua do sapo, centro da teia, sombra da coruja) com uma cauda, encolhendo até apagar em 0,55 s | `Ghost`, `drawShining` |
| Antecipação da coruja | um pio, e a sombra cresce no chão; segue o enxame e ganha borda dura quando o mergulho trava; os olhos acendem | `drawShadows`, `drawOwls` |
| Antecipação do sapo | incha 40% em meio segundo, coaxa e os olhos brilham mesmo no escuro | `drawWorld`, `drawShining` |
| Câmera que antecipa | olha 0,4 s à frente do líder, com suavização de meia-vida 0,22 s | `update` |
| Zoom com o enxame | de 1,0 até 0,74 conforme o enxame cresce | `update` |
| Haptics (Android) | pulso 18 ms; perda 35 ms forte; preso na teia 10 ms; notas do acorde 12 ms; topo da cascata 70 ms; estrelas 14 ms; derrota 60 ms | `buzz`, `PlatformApi.vibrate` na engine |

## O que mais entrou

| Elemento | O que acontece | Onde |
| --- | --- | --- |
| Coice do pulso | a câmera recua 3,5% e volta | `punch` |
| Clarão do pulso | uma onda de luz corre o mapa de luz e some em 1,4 s; faíscas saem do líder | `drawLights`, `react` |
| Rastro dos chamados | vaga-lumes chamados por um pulso riscam um fio de luz até o enxame | `leaveTrails` |
| Escala de resgates | cada resgate seguido toca uma nota acima, numa escala pentatônica | `Sounds.rescued` |
| Brasa no escuro | apagado, cada vaga-lume vira uma brasa quase invisível e a noite fecha um pouco | `drawShining`, `paint` |
| Contador que pula | o número do enxame cresce por um instante quando muda | `count_bump` |
| Câmera na vitória | vai até o cupinzeiro e aproxima | `update` |
| Estrelas | caem uma a uma, grandes demais e assentando, cada uma com uma nota mais alta | `endScreen`, `Sounds.star` |
| Vento visível | folhas cruzam a tela na direção e na força da rajada; o som do vento sobe junto | `blowLeaves`, `Sounds.ambience` |
| Teia que denuncia | quem fica preso pisca nervoso e acende os fios; os olhos da aranha aparecem | `drawShining` |
| Movimento contínuo | os vaga-lumes são desenhados um pouco à frente, pelo tempo que a simulação ainda não andou: sem tremor em telas de 90 ou 144 Hz | `drawShining` |
| Vegetação viva | copas, frondes e tufos balançam; folhas escuras passam em primeiro plano, mais rápido que o mundo | `drawWorld`, `drawCanopy` |
| Telas que surgem | cada tela e cada fase entram do escuro em 0,4 s | `fade` em `main.zig` |
| Lobo-guará | uiva ao chegar; as pernas compridas andam e os olhos devolvem a luz | `drawWorld`, `react` |

## O que só o aparelho diz

- A força e a duração dos haptics (foram conferidos numa JVM, não num
  motor de verdade).
- Se 70 ms de hit-stop incomodam quando a coruja leva três de uma vez.
- Se o recuo da câmera no pulso enjoa com pulsos seguidos.
