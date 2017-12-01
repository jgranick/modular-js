package modular.js;

import haxe.macro.*;
import haxe.macro.Type.ClassType;
import haxe.macro.Type.ClassField;
import haxe.ds.StringMap;
import modular.js.interfaces.IField;
import modular.js.interfaces.IKlass;

using StringTools;
using modular.js.StringExtender;


class Klass extends Module implements IKlass {
    public var members: StringMap<IField> = new StringMap();
    public var init = "";

    public var superClass:String = null;
    public var superClassDot:String = null;
    public var interfaces:Array<String> = new Array();
    public var isInterface:Bool;
    public var properties:Array<String> = new Array();

    public function isEmpty() {
        return code.trim() == "" && !members.keys().hasNext() && init.trim() == "";
    }
    
    public function getTSCode() {
        
        // TODO: Generate proper types
        // TODO: List getter/setter fields properly
        // TODO: Hide @:noCompletion fields
        
        var t = new haxe.Template('export class ::className::::if (superClassName != null):: extends ::superClassName::::end:: {
  constructor(...args: any[]);
::foreach members::  ::propertyAccessName::: any;
::end::::foreach statics::  static ::propertyAccessName::: any;
::end::
}
');
        
        function filterMember(member:IField) {
            var f = new Field(gen);
            f.name = member.name;
            f.fieldAccessName = f.name.asJSFieldAccess(gen.api);
            f.propertyAccessName = f.name.asJSPropertyAccess(gen.api);
            f.isStatic = member.isStatic;
            return f;
        }
        
        var data = {
            overrideBase: gen.isJSExtern(path),
            className: name,
            path: path,
            code: code,
            init: if (!globalInit && init != "") init else "",
            useHxClasses: gen.hasFeature('Type.resolveClass') || gen.hasFeature('Type.resolveEnum'),
            dependencies: [for (key in dependencies.keys()) key],
            interfaces: interfaces.join(','),
            superClass: superClassDot,
            superClassName: superClassDot != null ? superClassDot.split(".").pop() : null,
            members: [for (member in members.iterator()) filterMember(member)].filter(function(m) { return !m.isStatic; }),
            statics: [for (member in members.iterator()) filterMember(member)].filter(function(m) { return m.isStatic; })
        };
        
        return t.execute(data);
    }

    public function getCode() {
        var t = new haxe.Template('
// Class: ::path::
::if (dependencies.length > 0)::
// Dependencies:
    ::foreach dependencies::
//  ::__current__::
    ::end::
::end::
var ::className:: = (function () {
::if (overrideBase)::::if (useHxClasses)::$$hxClasses["::path::"] = ::className::::end::
::else::var ::className:: = ::if (useHxClasses == true)::$$hxClasses["::path::"] = ::end::::code::;
::if (interfaces != "")::::className::.__interfaces__ = [::interfaces::];
::end::::if (superClass != null)::::className::.__super__ = ::superClass::;
::className::.prototype = $$extend(::superClass::.prototype, {
::else::::className::.prototype = {
::end::::if (propertyString != "")::    "__properties__": {::propertyString::},
::end::::foreach members::  ::propertyAccessName::: ::code::,
::end:: __class__: ::className::
}::if (superClass != null)::)::end::;
::className::.__name__ = "::path::";::end::
::foreach statics::::className::::fieldAccessName:: = ::code::;
::end::::if (defineProperties != "")::::defineProperties::
::end::::if (init)::::init::
::end::
return ::className::;
}());
');
        function filterMember(member:IField) {
            var f = new Field(gen);
            f.name = member.name;
            f.fieldAccessName = f.name.asJSFieldAccess(gen.api);
            f.propertyAccessName = f.name.asJSPropertyAccess(gen.api);
            f.isStatic = member.isStatic;
            f.code = member.getCode();
            if (!f.isStatic) {
                f.code = f.code.indent(1);
            }
            return f;
        }

        var data = {
            overrideBase: gen.isJSExtern(path),
            className: name,
            path: path,
            code: code,
            init: if (!globalInit && init != "") init else "",
            useHxClasses: gen.hasFeature('Type.resolveClass') || gen.hasFeature('Type.resolveEnum'),
            dependencies: [for (key in dependencies.keys()) key],
            interfaces: interfaces.join(','),
            superClass: superClass,
            propertyString: [for (prop in properties) '"$prop":"$prop"'].join(','),
            defineProperties: "",
            members: [for (member in members.iterator()) filterMember(member)].filter(function(m) { return !m.isStatic; }),
            statics: [for (member in members.iterator()) filterMember(member)].filter(function(m) { return m.isStatic; })
        };
        
        if (!isInterface && properties.length > 0) {
            
            var propNames = new Map<String, Bool> ();
            var hasGetter = new Map<String, Bool> ();
            var hasSetter = new Map<String, Bool> ();
            
            var type, propName;
            
            for (prop in properties) {
                
                type = prop.substr (0, 3);
                propName = prop.substr (4);
                
                propNames.set (propName, true);
                if (type == "set") hasSetter.set (propName, true);
                else if (type == "get") hasGetter.set (propName, true);
                
            }
            
            data.defineProperties = 'Object.defineProperties($name.prototype, {\n';
            
            for (propName in propNames.keys ()) {
                
                if (hasGetter[propName] && hasSetter[propName]) {
                    data.defineProperties += '	"$propName": { get: $name.prototype.get_$propName, set: $name.prototype.set_$propName },\n';
                } else if (hasSetter[propName]) {
                    data.defineProperties += '	"$propName": { set: $name.prototype.set_$propName },\n';
                } else {
                    data.defineProperties += '	"$propName": { get: $name.prototype.get_$propName },\n';
                }
                
            }
            
            data.defineProperties += '});\n';
            
        }
        
        return t.execute(data);
    }

    public function addField(c: ClassType, f: ClassField) {
        gen.checkFieldName(c, f);
        gen.setContext(path + '.' + f.name);

        if(f.name.indexOf("get_") == 0 || f.name.indexOf("set_") == 0)
        {
            properties.push(f.name);
        }
        switch( f.kind )
        {
            case FVar(r, _):
                if( r == AccResolve ) return;
            default:
        }

        var field = new Field(gen);
        field.build(f, path);
        for (dep in field.dependencies.keys()) {
            addDependency(dep);
        }
        members.set(f.name, field);
    }

    public function addStaticField(c: ClassType, f: ClassField) {
        gen.checkFieldName(c, f);
        gen.setContext(path + '.' + f.name);
        var field = new Field(gen);
        field.build(f, path);
        field.isStatic = true;
        for (dep in field.dependencies.keys()) {
            addDependency(dep);
        }
        members.set(field.name, field);
    }

    public function build(c: ClassType) {
        name = c.name;
        path = gen.getPath(c);

        gen.setContext(path);
        if (c.init != null) {
            init = gen.api.generateStatement(c.init);
            if (name == 'Resource') {
                globalInit = true;
            } else {
                //init.indexOf('$name.') != -1 ||
                globalInit = name == 'Std';
            }
        }
        
        if (c.isInterface) isInterface = true;

        if( c.constructor != null ) {
            code = gen.api.generateStatement(c.constructor.get().expr());
        } else {
            code = "function() {}";
        }

        // Add Haxe type metadata
        if( c.interfaces.length > 0 ) {
            interfaces = [for (i in c.interfaces) gen.getTypeFromPath(gen.getPath(i.t.get()))];
        }
        if( c.superClass != null ) {
            gen.addDependency('extend_stub', this);
            superClassDot = gen.getPath(c.superClass.t.get());
            superClass = gen.getTypeFromPath(superClassDot);
        }
        for (dep in gen.getDependencies().keys()) {
            addDependency(dep);
        }

        if (!c.isExtern) {
            for( f in c.fields.get() ) {
                addField(c, f);
            }

            for( f in c.statics.get() ) {
                addStaticField(c, f);
            }
        }
    }
}
