/*
Copyright (c) Lyo Kato (lyo.kato _at_ gmail.com)

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE
LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION
OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION
WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
*/

package org.coderepos.net.xmpp
{
    import flash.events.EventDispatcher;
    import flash.events.Event;
    import flash.events.IOErrorEvent;
    import flash.events.SecurityErrorEvent;

    import org.coderepos.sasl.SASLMechanismFactory;
    import org.coderepos.sasl.SASLMechanismDefaultFactory;
    import org.coderepos.sasl.mechanisms.ISASLMechanism;

    import org.coderepos.xml.sax.XMLElementEventHandler;

    import org.coderepos.net.xmpp.handler.IXMPPStreamHandler;
    import org.coderepos.net.xmpp.handler.InitialHandler;
    import org.coderepos.net.xmpp.handler.TLSHandler;
    import org.coderepos.net.xmpp.handler.SASLHandler;
    import org.coderepos.net.xmpp.handler.ResourceBindingHandler;
    import org.coderepos.net.xmpp.handler.SessionEstablishmentHandler;
    import org.coderepos.net.xmpp.handler.InitialRosterHandler;
    import org.coderepos.net.xmpp.handler.CompletedHandler;

    import org.coderepos.net.xmpp.exceptions.XMPPProtocolError;
    import org.coderepos.net.xmpp.events.XMPPStreamEvent;
    import org.coderepos.net.xmpp.events.XMPPMessageEvent;
    import org.coderepos.net.xmpp.events.XMPPSubscriptionEvent;
    import org.coderepos.net.xmpp.events.XMPPPresenceEvent;
    import org.coderepos.net.xmpp.events.XMPPErrorEvent;
    import org.coderepos.net.xmpp.util.IDGenerator;
    import org.coderepos.net.xmpp.util.ReconnectionManager;
    import org.coderepos.net.xmpp.roster.RosterItem;
    import org.coderepos.net.xmpp.roster.RosterResource;

    public class XMPPStream extends EventDispatcher
    {
        private var _config:XMPPConfig;
        private var _connection:XMPPConnection;
        private var _handler:IXMPPStreamHandler;
        private var _attributes:Object;
        private var _features:XMPPServerFeatures;
        private var _saslFactory:SASLMechanismFactory;
        private var _jid:JID;
        private var _boundJID:JID;
        private var _idGenerator:IDGenerator;
        private var _reconnectionManager:ReconnectionManager;
        private var _roster:Object;
        private var _isReady:Boolean;

        public function XMPPStream(config:XMPPConfig)
        {
            _config      = config;
            _attributes  = {};
            _roster      = {};
            _isReady     = false;
            _features    = new XMPPServerFeatures();
            // XXX: JID validation ?
            _jid         = new JID(_config.username);
            _idGenerator = new IDGenerator("req:", 5);
            _saslFactory = new SASLMechanismDefaultFactory(
                _jid.node, _config.password, null, "xmpp", _config.host);
            _reconnectionManager = new ReconnectionManager(
                _config.reconnectionAcceptableInterval,
                _config.reconnectionMaxCountWithinInterval
            );
        }

        [InternalAPI]
        public function get applicationName():String
        {
            return _config.applicationName;
        }

        [InternalAPI]
        public function get applicationVersion():String
        {
            return _config.applicationVersion;
        }

        [InternalAPI]
        public function get applicationNode():String
        {
            return _config.applicationNode;
        }

        [InternalAPI]
        public function get applicationType():String
        {
            return _config.applicationType;
        }

        [InternalAPI]
        public function get applicationCategory():String
        {
            return _config.applicationCategory;
        }

        [InternalAPI]
        public function genNextID():String
        {
            return _idGenerator.generate();
        }

        [InternalAPI]
        public function get domain():String
        {
            return _jid.domain;
        }

        [InternalAPI]
        public function set features(features:XMPPServerFeatures):void
        {
            _features = features;
        }

        [ExternalAPI]
        public function getAttribute(key:String):String
        {
            return (key in _attributes) ? _attributes[key] : null;
        }

        [ExternalAPI]
        public function setAttribute(key:String, value:String):void
        {
            _attributes[key] = value;
        }

        [ExternalAPI]
        public function get connected():Boolean
        {
            return (_connection != null && _connection.connected);
        }

        [ExternalAPI]
        public function start():void
        {
            if (connected)
                throw new Error("already connected.");

            _connection = new XMPPConnection(_config);
            _connection.addEventListener(Event.CONNECT, connectHandler);
            _connection.addEventListener(Event.CLOSE, closeHandler);
            _connection.addEventListener(IOErrorEvent.IO_ERROR, ioErrorHandler);
            _connection.addEventListener(SecurityErrorEvent.SECURITY_ERROR, securityErrorHandler);
            _connection.addEventListener(XMPPErrorEvent.PROTOCOL_ERROR, protocolErrorHandler);
            _connection.connect();

            dispatchEvent(new XMPPStreamEvent(XMPPStreamEvent.START));
        }

        [ExternalAPI]
        public function send(s:String):void
        {
            if (connected)
                _connection.send(s);
        }

        [InternalAPI]
        public function setXMLEventHandler(handler:XMLElementEventHandler):void
        {
            if (connected)
                _connection.setXMLEventHandler(handler);
        }

        [InternalAPI]
        public function dispose():void
        {
            _handler = null;
            _isReady = false;
        }

        [InternalAPI]
        public function clearBuffer():void
        {
            trace("[CLEAR BUFFER]");
            if (connected)
                _connection.clearBuffer();
        }

        [ExternalAPI]
        public function disconnect():void
        {
            if (connected) {
                if (_isReady) {
                    send('<presence type="' + PresenceType.UNAVAILABLE + '"/>');
                    send('</stream:stream>');
                }
                _connection.disconnect();
                dispose();
                dispatchEvent(new Event(Event.CLOSE));
            } else {
                dispose();
            }
        }

        [InternalAPI]
        public function changeState(handler:IXMPPStreamHandler):void
        {
            _handler = handler;
            _handler.run();
        }

        [InternalAPI]
        public function initiated():void
        {
            if (_features.supportTLS) {
                dispatchEvent(new XMPPStreamEvent(XMPPStreamEvent.TLS_NEGOTIATING));
                changeState(new TLSHandler(this));
            } else {
                var mech:ISASLMechanism = findProperSASLMechanism();
                if (mech != null) {
                    dispatchEvent(new XMPPStreamEvent(XMPPStreamEvent.AUTHENTICATING));
                    changeState(new SASLHandler(this, mech));
                } else {
                    // XXX: Accept anonymous ?
                    throw new XMPPProtocolError(
                        "Server doesn't support SASL");
                }
            }
        }

        [InternalAPI]
        public function switchToTLS():void
        {
            if (connected)
                _connection.startTLS();
        }

        [InternalAPI]
        public function tlsNegotiated():void
        {
            var mech:ISASLMechanism = findProperSASLMechanism();
            if (mech != null) {
                dispatchEvent(new XMPPStreamEvent(XMPPStreamEvent.AUTHENTICATING));
                changeState(new SASLHandler(this, mech));
            } else {
                // XXX: Accept anonymous ?
                throw new XMPPProtocolError(
                    "Server doesn't support SASL");
            }
        }

        [InternalAPI]
        public function authenticated():void
        {
            if (_features.supportResourceBinding) {
                dispatchEvent(new XMPPStreamEvent(XMPPStreamEvent.BINDING_RESOURCE));
                changeState(new ResourceBindingHandler(this, _config.resource,
                    _config.resourceBindingMaxRetryCount));
            } else {
                // without Binding
                throw new XMPPProtocolError(
                    "Server doesn't support resource-binding");
            }
        }

        [InternalAPI]
        public function bindJID(jid:JID):void
        {
            _boundJID = jid;
            if (_features.supportSession) {
                dispatchEvent(new XMPPStreamEvent(XMPPStreamEvent.ESTABLISHING_SESSION));
                changeState(new SessionEstablishmentHandler(this));
            } else {
                dispatchEvent(new XMPPStreamEvent(XMPPStreamEvent.LOADING_ROSTER));
                changeState(new InitialRosterHandler(this));
            }
        }

        [InternalAPI]
        public function establishedSession():void
        {
            dispatchEvent(new XMPPStreamEvent(XMPPStreamEvent.LOADING_ROSTER));
            changeState(new InitialRosterHandler(this));
        }

        [ExternalAPI]
        public function get roster():Object
        {
            // should make iterator to encupsulate?
            return _roster;
        }

        [ExternalAPI]
        public function getRosterItem(jid:JID):RosterItem
        {
            var bareJID:String = jid.toBareJIDString();
            return (bareJID in _roster) ? _roster[bareJID] : null;
        }

        [ExternalAPI]
        public function getRosterResource(jid:JID):RosterResource
        {
            var resource:String = jid.resource;
            if (resource == null || resource.length == 0)
                throw new ArgumentError("This is not full JID: " + jid.toString());
            var item:RosterItem = getRosterItem(jid);
            if (item == null)
                return null;
            return item.getResource(resource);
        }

        [InternalAPI]
        public function initiatedRoster():void
        {
            updatedRoster();
            dispatchEvent(new XMPPStreamEvent(XMPPStreamEvent.READY));
            changeState(new CompletedHandler(this));
            _isReady = true;
        }

        [InternalAPI]
        public function updatedRoster():void
        {
            //dispatchEvent(new XMPPRosterEvent.UPDATED, _roster);
        }

        private function findProperSASLMechanism():ISASLMechanism
        {
            if (!_features.supportSASL)
                return null;
            var mech:ISASLMechanism = null;
            for each(var mechName:String in _features.saslMechs) {
                trace(mechName);
                mech = _saslFactory.getMechanism(mechName);
                if (mech != null)
                    break;
            }
            return mech;
        }

        [InternalAPI]
        public function setRosterItem(rosterItem:RosterItem):void
        {
            var jidString:String = rosterItem.jid.toBareJIDString();
            if (jidString in _roster) {
                _roster[jidString].update(rosterItem);
            } else {
                _roster[jidString] = rosterItem;
            }
        }

        [InternalAPI]
        public function changedChatState(from:JID, state:String):void
        {
            var jidString:String = from.toBareJIDString();
            var resource:String  = from.resource;
            /*
            if (jidString in _roster) {
                if (_roster[jidString].hasResource(resource)) {
                    _roster[jidString].getResource(resource).changeState(state);
                }
            }
            */

            // dispatchEvent(
            //    new XMPPChatStateEvent(XMPPChatState.STATE_CHANGED, from, state));
        }

        [InternalAPI]
        public function receivedMessage(message:XMPPMessage):void
        {
            dispatchEvent(new XMPPMessageEvent(XMPPMessageEvent.RECEIVED, message));
        }

        [ExternalAPI]
        public function sendMessage(to:JID, body:String):void
        {
            // if toJID is in roster and has active resource,
            // start 'chat' and use thread

            // or send normal message
        }

        [ExternalAPI]
        public function changePresence(show:String, status:String, priority:int=0):void
        {
            if (!_isReady)
                throw new Error("not ready");

            if (priority <= -128 && priority > 128)
                throw new ArgumentError("priority must be in between -127 and 128");

            var presenceTag:String = '<presence';

            var children:Array = [];
            if (show != null)
                children.push('<show>' + show + '</show>');
            if (status != null)
                children.push('<status>' + status + '</status>');
            if (priority != 0)
                children.push('<priority>' + String(priority) + '</priority>');

            // TODO: vcard avatar
            //var vCardTag:String = '<x xmlns="' + XMPPNamespace.VCARD_UPDATE + '">';
            //vCardTag += '<photo/>'
            //vCardTag += '</x>';

            if (children.length > 0) {
                presenceTag += '>';
                presenceTag += children.join('');
                presenceTag += '</presence>';
            } else {
                presenceTag += '/>';
            }
            send(presenceTag);
        }

        [InternalAPI]
        public function receivedPresence(presence:XMPPPresence):void
        {
            //var item:RosterItem = getRosterItem(presence.from);
            if (presence.isAvailable) {
                //item.setResource(presence.from.resource);
            } else {
                // XXX: remove the resource from roster
                //item.removeResource(presence.from.resource);
            }

            dispatchEvent(new XMPPPresenceEvent(
                XMPPPresenceEvent.RECEIVED, presence));
        }

        [InternalAPI]
        public function receivedSubscriptionRequest(sender:JID):void
        {
            dispatchEvent(new XMPPSubscriptionEvent(
                XMPPSubscriptionEvent.RECEIVED, sender));
        }

        [ExternalAPI]
        public function acceptSubscriptionRequest(contact:JID):void
        {
            if (_isReady)
                send(
                    '<presence to="' + contact.toBareJIDString()
                    + '" type="' + PresenceType.SUBSCRIBED + '"/>'
                );
        }

        [ExternalAPI]
        public function denySubscriptionRequest(contact:JID):void
        {
            if (_isReady)
                send(
                    '<presence to="' + contact.toBareJIDString()
                    + '" type="' + PresenceType.UNSUBSCRIBED + '"/>'
                );
        }

        [InternalAPI]
        public function receivedSubscriptionResponse(sender:JID, type:String):void
        {
            // dispatch only?
            // no need to edit some roster data, because roster-push comes.
        }

        [ExternalAPI]
        public function subscribe(contact:JID):void
        {
            if (_isReady)
                send('<presence to="' + contact.toBareJIDString()
                    + '" type="' + PresenceType.SUBSCRIBE + '" />');
        }

        [ExternalAPI]
        public function unsubscribe(contact:JID):void
        {
            if (_isReady && contact.toBareJIDString() in _roster)
                send('<presence to="' + contact.toBareJIDString()
                    + '" type="' + PresenceType.UNSUBSCRIBE + '" />');
        }

        [ExternalAPI]
        public function getLastSeconds(contact:JID):void
        {
            if (_isReady) // and check if this contacts support jappber:iq:last
                send(
                      '<iq to="'     + contact.toString()
                        + '" id="'   + genNextID()
                        + '" type="' + IQType.GET + '">'
                    + '<query xmlns="' + XMPPNamespace.IQ_LAST + '" />'
                    + '</iq>'
                );
        }

        [InternalAPI]
        public function gotLastSeconds(contact:JID, seconds:uint):void
        {
            // TODO: search person from roster and update 'seconds'
        }

        [ExternalAPI]
        public function getVersion(contact:JID):void
        {
            if (_isReady) // and check if this contacts support jappber:iq:version
                send(
                    '<iq to="'       + contact.toString()
                        + '" id="'   + genNextID()
                        + '" type="' + IQType.GET + '">'
                    + '<query xmlns="' + XMPPNamespace.IQ_VERSION + '" />'
                    + '</iq>'
                );
        }

        [InternalAPI]
        public function gotVersion(contact:JID, name:String,
            version:String, os:String):void
        {
            // TODO: search person from roster and update 'version'
        }

        /* MUC
        public function joinRoom(roomID:JID):void
        {
            send('<presence to="' + roomID.toBareJIDString() + '">');
        }

        public function sendMessageWithinRoom(roomID:JID, message:String):void
        {
            send(
                  '<message to="' + roomID.toBareJIDString()
                    + '" type="' + MessageType.GROUPCHAT + '">'
                + '<body>' + message + '</body>'
                + '</message>'
                );
        }

        public function partFromRoom(roomUserID:JID):void
        {
            send('<presence type="' + PresenceType.UNAVAILABLE
                + '" to="' + roomUserID.toString() + '"/>');
        }
        */

        private function connectHandler(e:Event):void
        {
            dispatchEvent(e);
            changeState(new InitialHandler(this));
        }

        private function closeHandler(e:Event):void
        {
            dispose();
            dispatchEvent(e);

            var canRetry:Boolean = _reconnectionManager.saveRecordAndVerify();
            if (canRetry) {
                start();
            } else {
                _reconnectionManager.clear();
            }
        }

        private function ioErrorHandler(e:IOErrorEvent):void
        {
            dispose();
            dispatchEvent(e);
        }

        private function securityErrorHandler(e:SecurityErrorEvent):void
        {
            dispose();
            dispatchEvent(e);
        }

        private function protocolErrorHandler(e:XMPPErrorEvent):void
        {
            dispose();
            dispatchEvent(e);
        }
    }
}

