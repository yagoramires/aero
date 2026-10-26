# Changelog

Formato baseado em [Keep a Changelog](https://keepachangelog.com/pt-BR/1.1.0/).

## [0.5.0] - 2026-10-25

### Adicionado
- Instalação pelo NeyHub: o Aero também vem como plugin (`Aero-0.5.0.neyplugin`) e roda dentro do NeyHub, que pede a Acessibilidade na tela de Permissões dele. Desinstalar pelo NeyHub para o encaixe na hora.
- Instalador `.dmg`, além do `.zip`.
- Configurações em **Ajuda ▾ → Configurações…** (ou, com o ícone da barra escondido, abrindo o Aero de novo pelo Finder): janela com o interruptor **Mostrar na barra de menus**, o estado da Acessibilidade, a tabela de atalhos e os botões de log e de reportar problema. No NeyHub, ficam no card do Aero.

### Alterado
- Ícone novo no padrão do NeyHub: o mesmo desenho, em fundo grafite com detalhe verde-limão.
- O menu da barra virou um painel no tema Grafite: blocos com o desenho de cada encaixe e o atalho, direções de monitor apagadas quando não há monitor daquele lado, aviso de Acessibilidade com **Conceder**, linha de atualização pronta com **Reiniciar agora** e **Ajuda ▾**.
- Atualização automática sem perguntar: o Aero confere 5 s depois de abrir e a cada 6 h, baixa sozinho e troca a versão quando você fecha o app. Depois de atualizar, mostra as novidades uma vez. O item **Buscar atualizações…** saiu do menu.
- Se o NeyHub já roda o Aero, o avulso avisa (um aviso só, o do Aero), sai dos itens de login e fecha, para não encaixar duas vezes.
- O build exige o certificado "Aero Local Signing"; não assina mais ad-hoc.
- Com uma janela já encaixada, encostar na borda leva pro espaço livre ao lado dela (a coluna inteira se estiver livre, senão o quadrante). Só encaixa encostando na borda, nunca no meio da tela.

### Corrigido
- No monitor de cima de dois empilhados, arrastar até embaixo não encaixava: o cursor passava direto pro monitor de baixo. Agora os últimos pixels antes dele contam como borda, e a borda de baixo encaixa no quadrante do lado do cursor (antes, só nos cantos).

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
