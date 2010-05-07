package
{
    import flash.events.EventDispatcher;
    import flash.events.Event;
    import flash.events.IOErrorEvent;
    import flash.events.SecurityErrorEvent;
    import flash.display.NativeWindow;
    import flash.desktop.NativeApplication;

    import org.coderepos.net.xmpp.stream.XMPPStream;
    import org.coderepos.net.xmpp.JID;
    import org.coderepos.net.xmpp.XMPPConfig;
    import org.coderepos.net.xmpp.XMPPMessage;
    import org.coderepos.net.xmpp.events.XMPPErrorEvent;
    import org.coderepos.net.xmpp.events.XMPPStreamEvent;
    import org.coderepos.net.xmpp.events.XMPPMessageEvent;

    public class DemoApp
    {
        private static var _app:DemoApp;

        public static function get app():DemoApp
        {
            if (_app == null)
                _app = new DemoApp();
            return _app;
        }

        private var _rootWindow:DemoXMPP;
        private var _setting:DemoSetting;
        private var _settingWindow:DemoSettingWindow;
        private var _chatWindows:Object;

        private var _conn:XMPPStream;

        public function DemoApp()
        {
           _setting = DemoSetting.load();
           _chatWindows = {};
        }

        public function get rootWindow():DemoXMPP
        {
            return _rootWindow;
        }

        public function set rootWindow(win:DemoXMPP):void
        {
            _rootWindow = win;
            _rootWindow.addEventListener(Event.CLOSING, shutDown);
        }

        private function shutDown(e:Event):void
        {
            saveSetting();
            closeAllWindows();
        }

        public function saveSetting():void
        {
            _setting.save();
        }

        private function closeAllWindows():void
        {
            var openedWindows:Array =
                NativeApplication.nativeApplication.openedWindows;
            for(var i:int = openedWindows.length - 1; i >= 0; --i) {
                var win:NativeWindow = openedWindows[i] as NativeWindow;
                win.close();
            }
        }

        public function openSettingWindow():void
        {
            if (_settingWindow == null || _settingWindow.closed) {
                _settingWindow = new DemoSettingWindow();
                _settingWindow.open();
                _settingWindow.setting = _setting;
            }
            _settingWindow.activate();
        }

        public function log(s:String):void
        {
            _rootWindow.log(s);
        }

        public function logLine(s:String):void
        {
            _rootWindow.logLine(s);
        }

        public function connect():void
        {
            var setting:XMPPConfig = _setting.genXMPPConfig();
            // TODO: validation
            _conn = new XMPPStream(setting);
            _conn.addEventListener(Event.CONNECT, connectHandler);
            _conn.addEventListener(Event.CLOSE, closeHandler);
            _conn.addEventListener(IOErrorEvent.IO_ERROR, ioErrorHandler);
            _conn.addEventListener(SecurityErrorEvent.SECURITY_ERROR, securityErrorHandler);
            _conn.addEventListener(XMPPErrorEvent.PROTOCOL_ERROR, protocolErrorHandler);
            _conn.addEventListener(XMPPErrorEvent.AUTH_ERROR, authErrorHandler);
            _conn.addEventListener(XMPPStreamEvent.START, streamStartHandler);
            _conn.addEventListener(XMPPStreamEvent.TLS_NEGOTIATING, streamNegotiatingHandler);
            _conn.addEventListener(XMPPStreamEvent.AUTHENTICATING, streamAuthenticatingHandler);
            _conn.addEventListener(XMPPStreamEvent.BINDING_RESOURCE, streamBindingHandler);
            _conn.addEventListener(XMPPStreamEvent.ESTABLISHING_SESSION, streamEstablishingHandler);
            _conn.addEventListener(XMPPStreamEvent.LOADING_ROSTER, streamLoadingHandler);
            _conn.addEventListener(XMPPStreamEvent.READY, streamReadyHandler);
            _conn.addEventListener(XMPPMessageEvent.RECEIVED, messageReceivedHandler);
            _conn.start();
        }

        private function messageReceivedHandler(e:XMPPMessageEvent):void
        {
            var msg:XMPPMessage = e.message;
            var sender:JID = msg.from;

            var bareJID:String = sender.toBareJIDString();
            var win:DemoChatWindow = _chatWindows[bareJID];
            if (win == null || win.closed) {
                win = new DemoChatWindow();
                win.open();
                win.target = bareJID;
            }
            _chatWindows[bareJID] = win;
            win.activate();
            win.pushMessage(msg);
        }

        public function streamStartHandler(e:XMPPStreamEvent):void
        {
            logLine("[STREAM_START]");
        }

        public function streamNegotiatingHandler(e:XMPPStreamEvent):void
        {
            logLine("[TLS_NEGOTIATING]");
        }

        public function streamAuthenticatingHandler(e:XMPPStreamEvent):void
        {
            logLine("[STREAM_AUTHENTICATING]");
        }

        public function streamBindingHandler(e:XMPPStreamEvent):void
        {
            logLine("[STREAM_RESOURCE_BINDING]");
        }

        public function streamEstablishingHandler(e:XMPPStreamEvent):void
        {
            logLine("[STREAM_SESSION_ESTABLISHING]");
        }

        public function streamLoadingHandler(e:XMPPStreamEvent):void
        {
            logLine("[STREAM_LOADING_ROSTER]");
        }

        public function streamReadyHandler(e:XMPPStreamEvent):void
        {
            logLine("[STREAM_READY]");
        }

        private function protocolErrorHandler(e:XMPPErrorEvent):void
        {
            logLine("[PROTOCOL_ERROR]");
            logLine(e.message);
        }

        private function authErrorHandler(e:XMPPErrorEvent):void
        {
            logLine("[AUTH_ERROR]");
            logLine(e.message);
        }

        private function connectHandler(e:Event):void
        {
            logLine("[CONNECTED]");
        }
        private function closeHandler(e:Event):void
        {
            logLine("[CONNECTION CLOSED]");
        }
        private function ioErrorHandler(e:IOErrorEvent):void
        {
            logLine("[IO_ERROR]");
            logLine(e.toString());
        }
        private function securityErrorHandler(e:SecurityErrorEvent):void
        {
            logLine("[SECURITY_ERROR]");
            logLine(e.toString());
        }
    }
}

