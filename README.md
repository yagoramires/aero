# Aero

Gerenciador de janelas para macOS que funciona como o do Windows: arraste até a borda, escolha a próxima janela e pronto, sem tela de configuração.

[Baixar a última versão](https://github.com/yagoramires/aero/releases/latest) · [Reportar problema](https://github.com/yagoramires/aero/issues/new)

Rectangle, Tiles e o encaixe nativo do macOS encaixam janelas, mas deixam de fora o **Snap Assist** (escolher a janela que vai ocupar o espaço que sobrou), a **divisória compartilhada** entre janelas lado a lado e a janela **voltar ao tamanho de antes** quando você tira ela do encaixe. O Aero faz isso e não tem nenhuma opção pra configurar.

## Instalar

1. Baixe o `Aero-x.y.z.zip` na [página de releases](https://github.com/yagoramires/aero/releases/latest), descompacte e arraste o **Aero.app** pra pasta **Aplicativos**.
2. Abra o Aero. Como ele não é assinado com um certificado pago da Apple, na primeira vez o macOS avisa que não conseguiu verificar o desenvolvedor. Clique com o botão direito no app → **Abrir**, ou vá em **Ajustes do Sistema → Privacidade e Segurança**, role até o fim e clique em **Abrir Mesmo Assim**. Pelo Terminal também resolve: `xattr -dr com.apple.quarantine /Applications/Aero.app`
3. Dê a permissão de Acessibilidade quando ele pedir (veja **Permissões**).
4. Opcional: no menu do Aero, marque **Abrir ao iniciar sessão**.

**Feche outros gerenciadores de janelas** (Rectangle, Tiles, Magnet...), porque eles usam os mesmos atalhos e o mesmo arraste. Se o encaixe nativo do macOS estiver ligado, desligue em **Ajustes do Sistema → Mesa e Dock → Janelas → Arrastar janelas para as bordas da tela**.

Requer macOS 14 ou mais novo. Roda nativo em Apple Silicon e Intel. Também dá pra compilar do código (veja **Build local**).

Instalador `.dmg` e instalação pelo NeyHub chegam na próxima versão.

### Desinstalar

1. No menu do Aero, desmarque **Abrir ao iniciar sessão** e clique em **Sair**.
2. Apague o **Aero.app** de Aplicativos.
3. Em **Ajustes do Sistema → Privacidade e Segurança → Acessibilidade**, remova o Aero da lista.
4. Opcional, pra apagar o estado salvo e os logs:
   `defaults delete local.aero; rm -rf ~/Library/Logs/Aero`

## Permissões

- **Acessibilidade** (Ajustes do Sistema → Privacidade e Segurança → Acessibilidade → Aero): necessária pra mover e redimensionar janelas de outros apps. O Aero começa a funcionar sozinho assim que a permissão é dada.
- Os atalhos globais usam Carbon e não precisam de permissão extra.
- Não usa Gravação de Tela: o Snap Assist mostra ícone e título das janelas, não miniaturas.

### Privacidade

O Aero não coleta nem envia nada sobre você ou suas janelas. A única conexão de rede é a consulta à
API pública do GitHub (`api.github.com`) pra saber se tem versão nova, e o download dela quando você
aceita atualizar. O log de depuração fica só no seu Mac.

## Como usar

### Encaixe

- **Arrastar até a borda**: lateral = metade, canto = quadrante, topo = maximizar. Uma prévia
  translúcida mostra onde a janela vai parar antes de você soltar. A faixa da barra de menu também
  conta como topo, então funciona até com um monitor empilhado em cima do outro.
- **Snap Assist**: depois de encaixar, aparecem as outras janelas abertas pra ocupar o espaço livre
  (clique, ou setas + Return; Esc fecha). Ele continua oferecendo até a tela encher, e não aparece
  se o espaço já estiver ocupado.
- **Ocupa o espaço que sobrou**: se a janela da esquerda foi alargada, a próxima encaixada à direita
  fica com o que sobrou, não com a metade fixa. Vale também para janelas posicionadas à mão.
- **Encaixar por cima**: soltar uma janela num lado já ocupado faz ela ficar no mesmo lugar e no
  mesmo tamanho da que já estava ali, por cima dela.
- **Divisória compartilhada**: com janelas lado a lado, redimensionar uma ajusta a vizinha. Se a
  vizinha chegar no tamanho mínimo dela, a outra para ali, sem ficar uma por cima da outra. Janelas
  encaixadas no mesmo lugar (uma por cima da outra, ou maximizadas) mudam de tamanho juntas. Vale
  pras janelas do mesmo Space, inclusive as minimizadas; as de outros Spaces não se mexem.
- **Volta ao tamanho original**: arrastar uma janela encaixada (ou `⌘↓` numa maximizada) devolve
  o tamanho de antes do primeiro encaixe, mesmo depois de trocar de encaixe várias vezes.
- **Vários monitores**: arraste entre eles ou use os atalhos.
- **Lembra dos encaixes** depois de reiniciar o app.

### Menu da barra

Clique no ícone do Aero na barra de menu:

| Item | O que faz |
| --- | --- |
| Metades, quadrantes, Maximizar, Restaurar | Aplica a posição na janela em foco. Cada item tem o desenho da área que a janela vai ocupar e mostra o atalho, quando existe. |
| Mover para outro monitor ▸ | Acima, abaixo, à esquerda ou à direita. Só ficam ativas as direções que têm monitor. |
| Abrir ao iniciar sessão | Liga o Aero junto com o Mac. |
| Buscar atualizações… | Confere se tem versão nova. Vira **Atualizar para a versão X…** quando já encontrou uma. |
| Ajuda ▸ | Mostra a versão instalada, abre o log de depuração e reporta problemas. |

### Problemas

Em **Ajuda → Reportar problema…** no menu, o Aero abre uma issue no GitHub já com a versão, o macOS
e os monitores preenchidos, e mostra no Finder o log pra você anexar. O log fica em
`~/Library/Logs/Aero/aero.log` e só registra as decisões do app (qual janela foi arrastada, pra qual
zona, por que um encaixe foi esquecido), nunca o conteúdo das janelas.

### Limitações

- O Snap Assist mostra ícone e título das janelas, não miniaturas (isso exigiria a permissão de
  Gravação de Tela).
- Na borda entre dois monitores lado a lado o cursor passa direto pro outro, então ali não dá pra
  encaixar arrastando (o Windows faz igual). Use os atalhos ou o menu.
- Só janelas do Space atual entram no Snap Assist.

## Atalhos

Mesma lógica do `Win` + setas do Windows:

| Atalho | O que faz |
| --- | --- |
| `⌘ ←` / `⌘ →` | Metade esquerda/direita. De novo, vai pro monitor ao lado. A seta oposta restaura. |
| `⌘ ↑` | Maximiza. Numa metade, vai pro quadrante de cima. |
| `⌘ ↓` | Restaura a maximizada. Numa metade, vai pro quadrante de baixo. Senão, minimiza. |
| `⇧⌘` + setas | Leva a janela pro monitor daquele lado (inclusive em cima/embaixo). |

Como no Windows, os atalhos valem no sistema todo. Por isso, enquanto o Aero estiver aberto, `⌘` + setas
deixam de ir pro começo/fim da linha e do documento nos campos de texto, e `⇧⌘` + setas deixam de
selecionar até lá. No Finder, `⌘↑`/`⌘↓` deixam de navegar entre pastas.

## Modos de exibição

O Aero não tem tela de configuração nem temas. As únicas escolhas são as do menu da barra: o ícone do Aero na barra de menus, as posições com o desenho da área que a janela vai ocupar e **Abrir ao iniciar sessão**.

## Atualizações

Desde a 0.4.0, o Aero confere ao abrir (e uma vez por dia) se tem versão nova e oferece instalar: ele baixa, troca o app e reabre sozinho, e a permissão de Acessibilidade continua valendo. A versão baixada só é instalada se tiver sido assinada pelo mesmo certificado do app em uso. Também dá pra conferir pelo menu (**Buscar atualizações…**).

Quem está na 0.1.0, 0.2.0 ou 0.3.0 precisa baixar a versão nova manualmente uma vez (é só substituir o Aero.app em Aplicativos). Daí em diante as atualizações chegam pelo próprio app.

## Build local

### Compilar

Só precisa das Command Line Tools (`xcode-select --install`), não do Xcode.

```sh
git clone https://github.com/yagoramires/aero.git && cd aero
scripts/setup-signing.sh   # uma vez: certificado local de assinatura (veja abaixo)
scripts/build.sh --run     # gera build/Aero.app e abre
```

O `setup-signing.sh` cria um certificado de assinatura local ("Aero Local Signing") no seu Chaveiro.
A permissão de Acessibilidade fica presa à assinatura do app: com assinatura ad-hoc ela muda a cada
build e o macOS para de confiar no app. Com um certificado fixo, a permissão sobrevive às
recompilações.

`scripts/make-icon.swift` gera o ícone (`Resources/AppIcon.icns`) a partir de código.

### Como funciona

| Arquivo | Papel |
| --- | --- |
| `Window.swift` | Lê e move janelas de outros apps pela API de Acessibilidade. As posições vêm do WindowServer, porque muitos apps (Electron, WebKit) demoram a atualizar a posição informada pela Acessibilidade. |
| `Geometry.swift` | Monitores, zonas de encaixe e detecção da borda sob o cursor. |
| `WindowManager.swift` | Estado dos encaixes, tamanho original, espaço livre, atalhos, divisória compartilhada e persistência. |
| `DragSnapper.swift` | Observa o mouse do sistema (event tap) pra detectar o arraste da janela e mostrar a prévia. |
| `SnapAssist.swift` | Painel com as janelas candidatas a ocupar o espaço livre. |
| `Hotkeys.swift` | Atalhos globais via Carbon (não precisam de permissão extra). |
| `Updater.swift` | Confere releases no GitHub, baixa, valida a assinatura e troca o app. |
| `Log.swift` | Log de depuração em `~/Library/Logs/Aero/`, com rotação. |
| `AppDelegate.swift` | Menu da barra, permissão e inicialização. |

### Depuração

```sh
defaults write local.aero debugBridge -bool true   # liga os comandos abaixo; reabra o app
scripts/debug.sh dump            # estado em /tmp/aero-debug.txt
scripts/debug.sh left            # simula ⌘← na janela em foco (também right, up, down)
scripts/debug.sh screen-up       # simula ⇧⌘↑ (também screen-down, screen-left, screen-right)
scripts/debug.sh check-update    # o mesmo que "Buscar atualizações…" no menu
scripts/debug.sh install-latest  # instala o último release sem perguntar (testa a atualização)
tail -f ~/Library/Logs/Aero/aero.log
```

### Publicar uma versão

1. Suba a versão em `Resources/Info.plist` (`CFBundleShortVersionString` e `CFBundleVersion`).
2. `scripts/build.sh --dist` gera o build universal e `dist/Aero-x.y.z.zip`.
3. Commit, push e `gh release create vX.Y.Z dist/Aero-x.y.z.zip`.

O release **precisa ser assinado com o mesmo certificado** das versões anteriores, senão os apps já
instalados recusam a atualização automática. Antes de trocar de Mac, exporte o "Aero Local Signing"
pelo app Acesso às Chaves (com a chave privada) e importe no Mac novo.

## Patch notes

Veja o [CHANGELOG](CHANGELOG.md).

## Licença

[MIT](LICENSE)
