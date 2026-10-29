import QtQuick
import "../"
import "js/chat.mjs" as Logic
import "js/util.mjs" as Util

Item {
    id: root
    required property var brain
    property var chat: null
    property var pending: ({})
    property int serial: 0
    property var delta: null
    property bool settingsOpen: false
    property bool configuring: false
    property var configuration: ({providers: [], models: []})
    property string feedback: ""
    property bool hiddenForShot: false
    signal send(var message)
    function rpc(method, args) {
        return new Promise(resolve => {
            const id = "c" + (++serial);
            const timeout = Util.setTimeout(() => {
                if (!pending[id]) return;
                delete pending[id];
                resolve({ok:false,error:"The Capri helper did not answer. Try again."});
            }, method === "send" ? 95000 : 20000);
            pending[id] = {resolve, timeout};
            send({t:"chat.request", id, method, args:args || {}});
        });
    }
    function ingest(m) {
        if (m.t === "chat.delta" && delta) delta(m);
        if (m.t !== "chat.result" || !pending[m.id]) return;
        const p = pending[m.id]; delete pending[m.id]; Util.clearTimeout(p.timeout); p.resolve(m.data);
    }
    function start() {
        if (chat || !brain.runtime) return;
        const r = brain.runtime;
        const host = {
            onChatDelta: fn => root.delta = m => fn({id:m.id,text:m.text}),
            chatStatus: () => root.rpc("status"),
            chatMemory: () => root.rpc("memory").then(data => Array.isArray(data) ? data : []),
            chatRemember: history => root.rpc("remember",{history}),
            chatSend: args => root.rpc("send",args),
            chatStop: id => root.rpc("stop",{id}),
            chatIntent: (text,apps,waitingWhen) => root.rpc("intent",{text,apps,waitingWhen}),
            focusOverlay: value => { brain.revision++; if(value) Qt.callLater(() => brain.bubble.focusChat()); },
            setConfig: patch => r.host.setConfig(patch),
            clock: (at,lang) => brain.clock(at,lang),
            now: () => new Date().toLocaleString(Qt.locale("en"),"dddd d MMMM yyyy HH:mm"),
            hideForShot: value => root.hiddenForShot = value,
            openOllama: () => root.showSettings()
        };
        for (const method of ["openApps","findApp","closeApp","findLaunch","launch","openSite","media","music","youtube","roblox","webSearch","searchFiles","openFile","screenshot"]) {
            host[method] = function() {
                const values = Array.prototype.slice.call(arguments);
                if (method === "screenshot") values.push(Capri.screenName);
                return root.rpc(method,{values}).then(data => {
                    if(data && data.ok === false) throw new Error(data.error);
                    return data;
                });
            };
        }
        r.panel.chatInput = {focus: () => brain.bubble.focusChat()};
        chat = new Logic.Chat({capri:r.capri,panel:r.panel,voice:{play(){}},host,brain:r.brain});
        chat.reminders = r.reminders; chat.bond = r.bond; chat.jealousy = r.jealousy;
        chat.onMessage = () => r.bond.add("chat",2);
        chat.onSetup = status => { root.feedback = status.error || status.code || ""; root.showSettings(); };
        chat.onBetterModel = () => root.showSettings();
        r.chat = chat; r.jealousy.chat = chat; r.brain.onTalk = () => root.open();
    }
    function open() {
        start(); brain.menuOpen = false;
        if(chat) chat.start().catch(error => root.fail(error));
    }
    function submit(text) {
        if(!chat || !text.trim() || text.length > 2000) return;
        chat.send(text.trim()).catch(error => root.fail(error));
    }
    function fail(error) {
        hiddenForShot = false;
        if(chat) {
            chat.turn = 0;
            if(chat.history.length && chat.history[chat.history.length-1].role === "user") chat.history.pop();
        }
        if(brain.runtime) {
            brain.runtime.panel.setChatBusy(false);
            brain.runtime.panel.stream(brain.labels.chat.failed + " " + String(error.message || error),{done:true});
        }
    }
    function showSettings() {
        if(chat) chat.close();
        if(brain.runtime) brain.runtime.panel.hide();
        brain.menuOpen = false; settingsOpen = true;
        rpc("config").then(data => {if(data.providers)configuration = data;});
    }
    function configure(patch) {
        if(configuring)return;
        configuring = true; feedback = "…";
        rpc("configure",patch).then(data => {
            configuring = false;
            if(data.ok) {configuration=data.config;feedback="";settingsOpen=false;root.open();}
            else feedback=data.error || "offline";
        });
    }
    function forget() {
        if(chat) {chat.close();chat.history=[];}
        if(brain.runtime)brain.runtime.panel.hide();
        rpc("forget");
    }
    Component.onDestruction: {if(chat)chat.close();}
}
