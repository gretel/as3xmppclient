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

package org.coderepos.net.xmpp.roster
{
    import org.coderepos.net.xmpp.JID;
    import org.coderepos.net.xmpp.XMPPPresence;
    import org.coderepos.net.xmpp.exceptions.XMPPProtocolError;
    import org.coderepos.xml.XMLElement;

    [Bindable]
    public class RosterItem
    {
        public static function fromElement(elem:XMLElement):RosterItem
        {
            var jidString:String = elem.getAttr("jid");
            if (jidString == null)
                throw new XMPPProtocolError("JID for roster elem not found");
            var jid:JID;
            try {
                jid = new JID(jidString);
            } catch (e:*) {
                throw new XMPPProtocolError("invalid JID format: " + jidString);
            }
            var item:RosterItem = new RosterItem(jid);
            var name:String = elem.getAttr("name");
            if (name != null)
                item.name = name;
            var subscription:String = elem.getAttr("subscription");
            if (subscription != null)
                item.subscription = subscription;
            var ask:String = elem.getAttr("ask");
            if (ask != null)
                item.ask = ask;

            var groups:Array = elem.getElements("group");
            for each(var group:XMLElement in groups) {
                item.addGroup(group.text);
            }
            return item;
        }

        private var _jid:JID;

        private var _name:String;
        private var _subscription:String;
        private var _ask:String;

        private var _groups:Object;
        private var _resources:Object;

        private var _version:ClientVersion;

        // XEP-0153 vCard based avatar
        private var _avatarHash:String;

        public function RosterItem(jid:JID):void
        {
            _jid       = jid;
            _groups    = {};
            _resources = {};
        }

        public function get jid():JID
        {
            return _jid;
        }

        public function addGroup(groupName:String):void
        {
            _groups[groupName] = 1;
        }

        public function belongsToGroup(groupName:String):Boolean
        {
            return (groupName in _groups);
        }

        public function hasResource(resource:String):Boolean
        {
            return (resource in _resources);
        }

        public function setResource(resource:String, presence:XMPPPresence):void
        {
            if (resource in _resources) {
                _resources[resource].updatePresence(presence);
            } else {
                _resources[resource] = new ContactResource(resource, presence);
            }
        }

        public function get hasAvtiveResource():Boolean
        {
            var resource:ContactResource;
            for (var prop:String in _resources) {
                resource = _resources[prop];
                if (resource.isActive)
                    return true;
            }
            return false;
        }

        public function getActiveResource():ContactResource
        {
            var chosen:ContactResource = null;
            var resource:ContactResource;
            for (var prop:String in _resources) {
                resource = _resources[prop];
                if (resource.isActive) {
                    if (chosen == null) {
                        chosen = resource;
                    } else if (chosen.priority < resource.priority) {
                        chosen = resource;
                    }
                }
            }
            return chosen;
        }

        public function getAllActiveResources():Array
        {
            var resources:Array = [];
            var resource:ContactResource;
            for (var prop:String in _resources) {
                resource = _resources[prop];
                if (resource.isActive) {
                    resources.push(resource);
                }
            }
            return resources;
        }

        public function getResource(resource:String):ContactResource
        {
            return (resource in _resources) ? _resources[resource] : null;
        }

        public function removeResource(resource:String):void
        {
            delete _resources[resource];
        }

        public function get status():String
        {
            var resource : ContactResource = getActiveResource();
            if(resource == null)
            {
                return null;
            }
            return resource.status;
        }

        public function get avatarHash():String
        {
            return _avatarHash;
        }

        public function set avatarHash(hash:String):void
        {
            _avatarHash = hash;
        }

        public function get groups():Array
        {
            var groupsArr:Array = [];
            for (var groupName:String in _groups)
                groupsArr.push(groupName);
            return groupsArr;
        }

        public function get resources():Array
        {
            var resourcesArr:Array = [];
            for (var resource:String in _resources)
                resourcesArr.push(resource);
            return resourcesArr;
        }

        public function updateItem(item:RosterItem):void
        {
            name         = item.name;
            subscription = item.subscription;
            ask          = item.ask;
            _groups      = [];
            for each(var groupName:String in item.groups) {
                addGroup(groupName);
            }
        }

        public function get name() : String {
            return _name;
        }

        public function set name(value : String) : void {
            _name = value;
        }

        public function get subscription() : String {
            return _subscription;
        }

        public function set subscription(value : String) : void {
            _subscription = value;
        }

        public function get ask() : String {
            return _ask;
        }

        public function set ask(value : String) : void {
            _ask = value;
        }

        public function get version() : ClientVersion {
            return _version;
        }

        public function set version(value : ClientVersion) : void {
            _version = value;
        }
    }
}

