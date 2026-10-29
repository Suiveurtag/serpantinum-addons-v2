// Panel arbitration is separate from its QML rendering; shares the body clock.
import { performance, setTimeout, clearTimeout } from './util.mjs';
export const PRIORITY = {info:1, idle:1, work:2, done:3, error:3, report:3, chat:3, alert:4, remind:4};
export class Panel {
  constructor(host) { this.host=host; this.current=null; this.visible=false; this.tickerAction=null; this.timer=null; this.tickerTimer=null; this.tickerAt=-Infinity; }
  say(msg) {
    if (this.host.quiet()) return false;
    const cur=this.current, p=PRIORITY[msg.kind] || 1;
    if (this.visible && cur) {
      if (cur.kind!==msg.kind && PRIORITY[cur.kind]>p && performance.now()-cur.at<2600) return false;
      if ((cur.reply && p<2) || (cur.report && p<3)) return false;
      if (cur.chat && !cur.guide && p<4) { if(p>=3) this.missed=Object.assign({},msg,{missedAt:performance.now()}); return false; }
    }
    this.leave();
    this.current=Object.assign({},msg,{at:performance.now()}); this.visible=true;
    clearTimeout(this.timer);
    this.host.changed(this);
    if(msg.hold) this.timer=setTimeout(()=>this.hide(),msg.hold);
    return true;
  }
  leave() { if(this.current && this.current.onLeave) this.current.onLeave(); }
  hide() { if (!this.visible) return; this.visible=false; clearTimeout(this.timer); this.leave(); this.current=null; this.host.changed(this);
    const missed=this.missed;this.missed=null;
    if(missed && performance.now()-missed.missedAt<=120000)setTimeout(()=>{if(!this.visible)this.say(missed);},0);
  }
  clearKind(kind) { if(this.current && this.current.kind===kind) this.hide(); }
  setTicker(action) {
    clearTimeout(this.tickerTimer);
    if(action && performance.now()-this.tickerAt<380) { this.tickerTimer=setTimeout(()=>this.setTicker(action),380-(performance.now()-this.tickerAt)); return; }
    this.tickerAt=performance.now(); this.tickerAction=action; this.host.changed(this);
  }
  updateLog(log) { if(this.current) { this.current.log=log.slice(-4); this.host.changed(this); } }
  setActions(actions, onAction) { if(this.current) { this.current.actions=actions; if(onAction)this.current.onAction=onAction; this.host.changed(this); } }
  patch(values) { if(this.current) {Object.assign(this.current,values);this.host.changed(this);} }
  setFace(face) {this.patch({face});}
  setChatBusy(busy) {this.patch({chatBusy:busy});}
  chatTurn(values) {this.patch(Object.assign({line:'',reply:'',actions:[],chatDone:false},values));}
  stream(line, options={}) {this.patch({line,chatDone:!!options.done});}
  relabel(id,label) { if(this.current && this.current.actions) { this.current.actions=this.current.actions.map(a=>a.id===id?Object.assign({},a,{label}):a); this.host.changed(this); } }
  snapshot(fn) { return this.host.snapshot(fn); }
  action(id) { if(this.current && this.current.onAction) this.current.onAction(id); }
}
