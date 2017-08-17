require("../../spec_helper")

_ = require("lodash")
EE = require("events")
menu = require("#{root}../lib/gui/menu")
Windows = require("#{root}../lib/gui/windows")
electron = require("#{root}../lib/browsers/electron")
savedState = require("#{root}../lib/saved_state")
Automation = require("#{root}../lib/automation")

describe "lib/browsers/electron", ->
  beforeEach ->
    @url = "https://foo.com"
    @state = {}
    @options = {}
    @automation = Automation.create("foo", "bar", "baz")
    @win = _.extend(new EE(), {
      close: @sandbox.stub()
      loadURL: @sandbox.stub()
      webContents: {
        session: {
          cookies: {
            get: @sandbox.stub()
            set: @sandbox.stub()
            remove: @sandbox.stub()
          }
        }
      }
    })

  context ".open", ->
    beforeEach ->
      @sandbox.stub(electron, "_render").resolves(@win)
      state = savedState()
      @sandbox.stub(state, "get").resolves(@state)

    it "calls render with url, state, and options", ->
      electron.open("electron", @url, @options, @automation)
      .then =>
        expect(electron._render).to.be.calledWith(@url, @state, @options)

    it "returns custom object emitter interface", ->
      electron.open("electron", @url, @options, @automation)
      .then (obj) =>
        expect(obj.browserWindow).to.eq(@win)
        expect(obj.kill).to.be.a("function")
        expect(obj.removeAllListeners).to.be.a("function")

  context "._launch", ->
    beforeEach ->
      @sandbox.stub(menu, "set")
      @sandbox.stub(electron, "_setProxy").resolves()

    it "sets dev tools in menu", ->
      electron._launch(@win, @url, @options)
      .then ->
        expect(menu.set).to.be.calledWith({withDevTools: true})

    it "sets proxy if options.proxyServer", ->
      electron._launch(@win, @url, @options)
      .then ->
        expect(electron._setProxy).not.to.be.called
      .then =>
        electron._launch(@win, @url, {proxyServer: "foo"})
      .then =>
        expect(electron._setProxy).to.be.calledWith(@win.webContents, "foo")

    it "calls win.loadURL with url", ->
      electron._launch(@win, @url, @options)
      .then =>
        expect(@win.loadURL).to.be.calledWith(@url)

    it "resolves with win", ->
      electron._launch(@win, @url, @options)
      .then (win) =>
        expect(win).to.eq(@win)

  context "._render", ->
    beforeEach ->
      @newWin = {}
      @newOptions = {}

      @sandbox.stub(menu, "set")
      @sandbox.stub(electron, "_setProxy").resolves()
      @sandbox.stub(electron, "_launch").resolves()
      @sandbox.stub(electron, "_defaultOptions").withArgs(@options).returns(@newOptions)
      @sandbox.stub(Windows, "create").withArgs(@newOptions).returns(@newWin)

    it "creates window instance and calls launch with window", ->
      electron._render(@url, @state, @options)
      .then =>
        expect(Windows.create).to.be.calledWith(@options)
        expect(electron._launch).to.be.calledWith(@newWin, @url, @newOptions)

  context "._defaultOptions", ->
    beforeEach ->
      @sandbox.stub(menu, "set")

    it "uses default width if there isn't one saved", ->
      opts = electron._defaultOptions(@state, @options)
      expect(opts.width).to.eq(1280)

    it "uses saved width if there is one", ->
      opts = electron._defaultOptions({browserWidth: 1024}, @options)
      expect(opts.width).to.eq(1024)

    it "uses default height if there isn't one saved", ->
      opts = electron._defaultOptions(@state, @options)
      expect(opts.height).to.eq(720)

    it "uses saved height if there is one", ->
      opts = electron._defaultOptions({browserHeight: 768}, @options)
      expect(opts.height).to.eq(768)

    it "uses saved x if there is one", ->
      opts = electron._defaultOptions({browserX: 200}, @options)
      expect(opts.x).to.eq(200)

    it "uses saved y if there is one", ->
      opts = electron._defaultOptions({browserY: 300}, @options)
      expect(opts.y).to.eq(300)

    it "tracks browser state", ->
      opts = electron._defaultOptions({browserY: 300}, @options)

      args = _.pick(opts.trackState, "width", "height", "x", "y", "devTools")

      expect(args).to.deep.eq({
        width: "browserWidth"
        height: "browserHeight"
        x: "browserX"
        y: "browserY"
        devTools: "isBrowserDevToolsOpen"
      })

    it ".onFocus", ->
      opts = electron._defaultOptions(@state, @options)
      opts.onFocus()
      expect(menu.set).to.be.calledWith({withDevTools: true})

    describe ".onNewWindow", ->
      beforeEach ->
        @sandbox.stub(electron, "_launchChild").resolves(@win)

      it "passes along event, url, parent window and options", ->
        opts = electron._defaultOptions(@state, @options)

        event = {}
        parentWindow = {
          on: @sandbox.stub()
        }

        opts.onNewWindow.call(parentWindow, event, @url)

        expect(electron._launchChild).to.be.calledWith(event, @url, parentWindow, @state, @options)

  ## TODO: these all need to be updated
  context.skip "._launchChild", ->
    beforeEach ->
      @childWin = _.extend(new EE(), {
        close: @sandbox.stub()
        isDestroyed: @sandbox.stub().returns(false)
        webContents: new EE()
      })

      Windows.create.onCall(1).resolves(@childWin)

      @event = {preventDefault: @sandbox.stub()}
      @win.getPosition = -> [4, 2]

      @openNewWindow = (options) =>
        launcher.launch("electron", @url, options).then =>
          @win.webContents.emit("new-window", @event, "some://other.url")

    it "prevents default", ->
      @openNewWindow().then =>
        expect(@event.preventDefault).to.be.called

    it "creates child window", ->
      @openNewWindow().then =>
        args = Windows.create.lastCall.args[0]
        expect(Windows.create).to.be.calledTwice
        expect(args.url).to.equal("some://other.url")
        expect(args.minWidth).to.equal(100)
        expect(args.minHeight).to.equal(100)

    it "offsets it from parent by 100px", ->
      @openNewWindow().then =>
        args = Windows.create.lastCall.args[0]
        expect(args.x).to.equal(104)
        expect(args.y).to.equal(102)

    it "passes along web security", ->
      @openNewWindow({chromeWebSecurity: false}).then =>
        args = Windows.create.lastCall.args[0]
        expect(args.chromeWebSecurity).to.be.false

    it "sets unique PROJECT type on each new window", ->
      @openNewWindow().then =>
        firstArgs = Windows.create.lastCall.args[0]
        expect(firstArgs.type).to.match(/^PROJECT-CHILD-\d/)
        @win.webContents.emit("new-window", @event, "yet://another.url")
        secondArgs = Windows.create.lastCall.args[0]
        expect(secondArgs.type).to.match(/^PROJECT-CHILD-\d/)
        expect(firstArgs.type).not.to.equal(secondArgs.type)

    it "set newGuest on child window", ->
      @openNewWindow()
      .then ->
        Promise.delay(1)
      .then =>
        expect(@event.newGuest).to.equal(@childWin)

    it "sets menu with dev tools on creation", ->
      @openNewWindow().then =>
        ## once for main window, once for child
        expect(menu.set).to.be.calledTwice
        expect(menu.set).to.be.calledWith({withDevTools: true})

    it "sets menu with dev tools on focus", ->
      @openNewWindow().then =>
        Windows.create.lastCall.args[0].onFocus()
        ## once for main window, once for child, once for focus
        expect(menu.set).to.be.calledThrice
        expect(menu.set).to.be.calledWith({withDevTools: true})

    it "it closes the child window when the parent window is closed", ->
      @openNewWindow()
      .then ->
        Promise.delay(1)
      .then =>
        @win.emit("close")
        expect(@childWin.close).to.be.called

    it "does not close the child window when it is already destroyed", ->
      @openNewWindow()
      .then ->
        Promise.delay(1)
      .then =>
        @childWin.isDestroyed.returns(true)
        @win.emit("close")
        expect(@childWin.close).not.to.be.called

    it "does the same things for children of the child window", ->
      @grandchildWin = _.extend(new EE(), {
        close: @sandbox.stub()
        isDestroyed: @sandbox.stub().returns(false)
        webContents: new EE()
      })
      Windows.create.onCall(2).resolves(@grandchildWin)
      @childWin.getPosition = -> [104, 102]

      @openNewWindow().then =>
        @childWin.webContents.emit("new-window", @event, "yet://another.url")
        args = Windows.create.lastCall.args[0]
        expect(Windows.create).to.be.calledThrice
        expect(args.url).to.equal("yet://another.url")
        expect(args.type).to.match(/^PROJECT-CHILD-\d/)
        expect(args.x).to.equal(204)
        expect(args.y).to.equal(202)

  context "._setProxy", ->
    it "sets proxy rules for webContents", ->
      webContents = {
        session: {
          setProxy: @sandbox.stub().yieldsAsync()
        }
      }

      electron._setProxy(webContents, "proxy rules")
      .then ->
        expect(webContents.session.setProxy).to.be.calledWith({
          proxyRules: "proxy rules"
        })