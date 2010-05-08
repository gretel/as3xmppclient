package org.coderepos.net.xmpp.roster
{
    [Bindable]
    public class ClientVersion
    {
        private var _name : String;
        private var _version : String;
        private var _os : String;

        public function ClientVersion(name : String, version : String, os : String)
        {
            _name = name;
            _version = version;
            _os = os;
        }

        public function get name() : String {
            return _name;
        }

        public function set name(value : String) : void {
            _name = value;
        }

        public function get version() : String {
            return _version;
        }

        public function set version(value : String) : void {
            _version = value;
        }

        public function get os() : String {
            return _os;
        }

        public function set os(value : String) : void {
            _os = value;
        }
    }
}

