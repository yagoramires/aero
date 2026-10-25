# Changelog

Formato baseado em [Keep a Changelog](https://keepachangelog.com/pt-BR/1.1.0/).

## [0.4.1] - 2026-10-22

### Corrigido
- Encaixar por cima: soltar uma janela num lado que já tem uma janela encaixada faz ela ficar no mesmo lugar e no mesmo tamanho da que estava ali, por cima dela. Antes ela pegava a metade fixa da tela.
- Janelas empilhadas mudam de tamanho juntas, inclusive as maximizadas, e a vizinha do lado acompanha a borda.
- A divisória compartilhada só mexe nas janelas do mesmo Space (inclusive as minimizadas).
- Tamanho mínimo: se a vizinha não consegue ficar menor, a janela que está sendo redimensionada para ali.
- O Snap Assist não conta mais janelas de outros Spaces como ocupando espaço.
- Atualização adiada ("Depois" ou "Ver novidades") não é oferecida de novo sozinha; o menu continua mostrando.

### Documentação
- README completo (menu, atualizações, desinstalar, privacidade, publicar versão).

## [0.4.0] - 2026-10-22

### Adicionado
- Atualização automática: ao abrir, e uma vez por dia, o Aero confere se tem versão nova e oferece instalar, sem pedir a Acessibilidade de novo.
- Log de depuração em `~/Library/Logs/Aero/aero.log`, só com as decisões do app.
- Menu Ajuda com a versão, **Mostrar log de depuração** e **Reportar problema…**.

## [0.3.0] - 2026-10-22

### Adicionado
- Menu da barra com as posições da tela (metades, quadrantes, maximizar e restaurar), cada uma com o desenho da área e o atalho alinhado à direita.
- **Mover para outro monitor** virou submenu, com só as direções que têm monitor ativas.

## [0.2.0] - 2026-10-22

### Alterado
- Atalhos com `⌘` + setas, como o `Win` + setas do Windows (antes eram `⌃⌥` + setas), e `⇧⌘` + setas para trocar de monitor.

## [0.1.0] - 2026-10-22

### Adicionado
- Primeira versão: encaixe por arraste (lateral = metade, canto = quadrante, topo ou barra de menu = maximizar) com prévia antes de soltar.
- Snap Assist para escolher a janela que ocupa o espaço que sobrou.
- Encaixe que ocupa só o espaço livre ao lado de janelas já posicionadas.
- Divisória compartilhada entre janelas lado a lado, respeitando o tamanho mínimo de cada app.
- A janela volta ao tamanho original ao ser desencaixada.
- Atalhos `⌃⌥` + setas e `⌃⌥⇧` + setas para trocar de monitor.
- Lembra dos encaixes depois de reiniciar.
