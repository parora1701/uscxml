# Copyright (C) 2005, 2006 Nikolas Zimmermann <zimmermann@kde.org>
# Copyright (C) 2006 Anders Carlsson <andersca@mac.com>
# Copyright (C) 2006 Samuel Weinig <sam.weinig@gmail.com>
# Copyright (C) 2006 Alexey Proskuryakov <ap@webkit.org>
# Copyright (C) 2006 Apple Computer, Inc.
# Copyright (C) 2007, 2008, 2009, 2012 Google Inc.
# Copyright (C) 2009 Cameron McCormack <cam@mcc.id.au>
# Copyright (C) Research In Motion Limited 2010. All rights reserved.
# Copyright (C) 2010 Nokia Corporation and/or its subsidiary(-ies)
# Copyright (C) 2012 Ericsson AB. All rights reserved.
# Copyright (C) 2013 Stefan Radomski <radomski@tk.informatik.tu-darmstadt.de>
#
# This library is free software; you can redistribute it and/or
# modify it under the terms of the GNU Library General Public
# License as published by the Free Software Foundation; either
# version 2 of the License, or (at your option) any later version.
#
# This library is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
# Library General Public License for more details.
#
# You should have received a copy of the GNU Library General Public License
# along with this library; see the file COPYING.LIB.  If not, write to
# the Free Software Foundation, Inc., 59 Temple Place - Suite 330,
# Boston, MA 02111-1307, USA.
#

package CodeGeneratorArabicaV8;

use strict;
use Data::Dumper;
use Carp qw/longmess cluck confess/;

use constant FileNamePrefix => "V8";

my $codeGenerator;


my @headerContent = ();
my @implContentHeader = ();
my @implContent = ();
my @implContentDecls = ();
my %implIncludes = ();
my %headerIncludes = ();

# Default .h template
my $headerTemplate = << "EOF";
/*
    This file is part of the Wrapper open source project.
    This file has been generated by generate-bindings.pl. DO NOT MODIFY!

    This library is free software; you can redistribute it and/or
    modify it under the terms of the GNU Library General Public
    License as published by the Free Software Foundation; either
    version 2 of the License, or (at your option) any later version.

    This library is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
    Library General Public License for more details.

    You should have received a copy of the GNU Library General Public License
    along with this library; see the file COPYING.LIB.  If not, write to
    the Free Software Foundation, Inc., 59 Temple Place - Suite 330,
    Boston, MA 02111-1307, USA.
*/
EOF

# Default constructor
sub new
{
    my $object = shift;
    my $reference = { };

    $codeGenerator = shift;

    bless($reference, $object);
    return $reference;
}

sub GenerateInterface
{
    my $object = shift;
    my $interface = shift;

    # Start actual generation
    if ($interface->extendedAttributes->{"Callback"}) {
        die();
        $object->GenerateCallbackHeader($interface);
        $object->GenerateCallbackImplementation($interface);
    } else {
        $object->GenerateHeader($interface);
        $object->GenerateImplementation($interface);
    }
}

sub AddToImplIncludes
{
    my $header = shift;
    my $conditional = shift;

    if ($header eq "V8bool.h") {
      confess();
    }

    if (not $conditional) {
        $implIncludes{$header} = 1;
    } elsif (not exists($implIncludes{$header})) {
        $implIncludes{$header} = $conditional;
    } else {
        my $oldValue = $implIncludes{$header};
        if ($oldValue ne 1) {
            my %newValue = ();
            $newValue{$conditional} = 1;
            foreach my $condition (split(/\|/, $oldValue)) {
                $newValue{$condition} = 1;
            }
            $implIncludes{$header} = join("|", sort keys %newValue);
        }
    }
}

sub GenerateHeader
{
    my $object = shift;
    my $interface = shift;
    my $interfaceName = $interface->name;
    my $extensions = $interface->extendedAttributes;
#    print Dumper($extensions);

    # Copy contents of parent interfaces except the first parent.
    my @parents;
    $codeGenerator->AddMethodsConstantsAndAttributesFromParentInterfaces($interface, \@parents, 1);
    $codeGenerator->LinkOverloadedFunctions($interface);

    # - Add default header template
    push(@headerContent, GenerateHeaderContentHeader($interface));

    $headerIncludes{"string"} = 1;
    $headerIncludes{"uscxml/plugins/datamodel/ecmascript/v8/V8DOM.h"} = 1;
    $headerIncludes{"DOM/Node.hpp"} = 1;
    $headerIncludes{"v8.h"} = 1;

    foreach (@{$interface->parents}) {
        my $parent = $_;
        $headerIncludes{"V8${parent}.h"} = 1;
    }

    push(@headerContent, "#include \<string\>\n");
    foreach my $headerInclude (sort keys(%headerIncludes)) {
        if ($headerInclude =~ /wtf|v8\.h/) {
            push(@headerContent, "#include \<${headerInclude}\>\n");
        } else {
            push(@headerContent, "#include \"${headerInclude}\"\n");
        }
    }

    push(@headerContent, "");
    push(@headerContent, "\nnamespace Arabica {");
    push(@headerContent, "\nnamespace DOM {\n");

    push(@headerContent, "\nclass V8${interfaceName} {");
    push(@headerContent, "\npublic:");

    my $wrapperType = IdlToWrapperType($interfaceName);
    push(@headerContent, <<END);

    struct V8${interfaceName}Private {
      V8DOM* dom;
      ${wrapperType}* nativeObj;
    };
END

    if ($extensions->{'DontDestroyWrapped'}) {
      push(@headerContent, "\n    V8_DESTRUCTOR_KEEP_WRAPPED(V8${interfaceName}Private);");
    } else {
      push(@headerContent, "\n    V8_DESTRUCTOR(V8${interfaceName}Private);");
    }
    push(@headerContent, "\n    static bool hasInstance(v8::Handle<v8::Value>);");
    push(@headerContent, "\n");


    # callbacks for actual functions
    foreach my $function (@{$interface->functions}) {
        my $name = $function->signature->name;
        my $attrExt = $function->signature->extendedAttributes;
        my $custom = ($attrExt->{'Custom'} ? "Custom" : "");
        push(@headerContent, "\n    static v8::Handle<v8::Value> ${name}${custom}Callback(const v8::Arguments&);");
    }
    push(@headerContent, "\n");

    # attribute getter and setters
    foreach my $attribute (@{$interface->attributes}) {
        my $name = $attribute->signature->name;
        my $attrExt = $attribute->signature->extendedAttributes;
        my $customGetter = ($attrExt->{'CustomGetter'} ? "Custom" : "");
        my $customSetter = ($attrExt->{'CustomSetter'} ? "Custom" : "");
        push(@headerContent, "\n    static v8::Handle<v8::Value> ${name}${customGetter}AttrGetter(v8::Local<v8::String> property, const v8::AccessorInfo& info);");
        if (!IsReadonly($attribute)) {
          push(@headerContent, "\n    static void ${name}${customSetter}AttrSetter(v8::Local<v8::String> property, v8::Local<v8::Value> value, const v8::AccessorInfo& info);");
        }
    }

    if ($extensions->{'CustomIndexedGetter'}) {
      push(@headerContent, "\n    static v8::Handle<v8::Value> indexedPropertyCustomGetter(uint32_t, const v8::AccessorInfo&);");
    }
    if ($extensions->{'CustomIndexedSetter'}) {
      push(@headerContent, "\n    static v8::Handle<v8::Value> indexedPropertyCustomSetter(uint32_t, v8::Local<v8::Value>, const v8::AccessorInfo&);");
    }
    push(@headerContent, "\n");

    GenerateClassPrototypeHeader($interface);

    push(@headerContent, "\n};\n\n}\n}\n\n");
    push(@headerContent, "#endif // V8${interfaceName}" . "_h\n");

}

#
# Write class template prototype constructor
#
sub GenerateClassPrototypeHeader
{
  my $interface = shift;
  my $interfaceName = $interface->name;
  my $extensions = $interface->extendedAttributes;

  push(@headerContent, "\n    static v8::Persistent<v8::FunctionTemplate> Tmpl;\n");
  push(@headerContent, <<END);
    static v8::Handle<v8::FunctionTemplate> getTmpl() {
        if (Tmpl.IsEmpty()) {
            v8::Handle<v8::FunctionTemplate> tmpl = v8::FunctionTemplate::New();
            tmpl->SetClassName(v8::String::New("${interfaceName}"));
            tmpl->ReadOnlyPrototype();

            v8::Local<v8::ObjectTemplate> instance = tmpl->InstanceTemplate();
            v8::Local<v8::ObjectTemplate> prototype = tmpl->PrototypeTemplate();
            (void)prototype; // surpress unused warnings
            
            instance->SetInternalFieldCount(1);
END

  push(@headerContent, "\n");
  foreach my $attribute (@{$interface->attributes}) {
    my $name = $attribute->signature->name;
    my $attrExt = $attribute->signature->extendedAttributes;
    my $customGetter = ($attrExt->{'CustomGetter'} ? "Custom" : "");
    my $customSetter = ($attrExt->{'CustomSetter'} ? "Custom" : "");
    my $getter = "V8${interfaceName}::${name}${customGetter}AttrGetter";
    my $setter = (IsReadonly($attribute) ? "0" : "V8${interfaceName}::${name}${customSetter}AttrSetter");
    push(@headerContent, <<END);
            instance->SetAccessor(v8::String::NewSymbol("${name}"), ${getter}, ${setter},
                                  v8::External::New(0), static_cast<v8::AccessControl>(v8::DEFAULT), static_cast<v8::PropertyAttribute>(v8::None));
END
    }

  if ($extensions->{'CustomIndexedGetter'} || $extensions->{'CustomIndexedSetter'}) {
    my $indexedGetter = ($extensions->{'CustomIndexedGetter'} ? "V8${interfaceName}::indexedPropertyCustomGetter" : 0);
    my $indexedSetter = ($extensions->{'CustomIndexedSetter'} ? "V8${interfaceName}::indexedPropertyCustomSetter" : 0);
    push(@headerContent, "\n            instance->SetIndexedPropertyHandler(${indexedGetter}, ${indexedSetter});");
  }

  push(@headerContent, "\n");
  foreach my $function (@{$interface->functions}) {
    my $name = $function->signature->name;
    my $attrExt = $function->signature->extendedAttributes;
    my $custom = ($attrExt->{'Custom'} ? "Custom" : "");
  push(@headerContent, <<END);
            prototype->Set(v8::String::NewSymbol("${name}"),
                           v8::FunctionTemplate::New(V8${interfaceName}::${name}${custom}Callback, v8::Undefined()), static_cast<v8::PropertyAttribute>(v8::DontDelete));
END
  }

  push(@headerContent, "\n");
  foreach my $constant (@{$interface->constants}) {
    my $name = $constant->name;
    my $value = $constant->value;
    my $type = IdlToV8Type($constant->type);
    push(@headerContent, <<END);
            tmpl->Set(v8::String::NewSymbol("${name}"), ${type}::New(${value}), static_cast<v8::PropertyAttribute>(v8::ReadOnly | v8::DontEnum));
            prototype->Set(v8::String::NewSymbol("${name}"), ${type}::New(${value}), static_cast<v8::PropertyAttribute>(v8::ReadOnly | v8::DontEnum));
END
  }

  push(@headerContent, "\n");
  if (@{$interface->parents}) {
    my $parent = @{$interface->parents}[0];
    push(@headerContent, "            tmpl->Inherit(V8${parent}::getTmpl());\n");
  }
  push(@headerContent, <<END);
            Tmpl = v8::Persistent<v8::FunctionTemplate>::New(tmpl);
        }
        return Tmpl;
    }

END
  
}

sub GenerateImplementationAttributes
{
  my $interface = shift;
  my $interfaceName = $interface->name;
  my $extensions = $interface->extendedAttributes;
  
  # Generate property accessors for attributes.
  for (my $index = 0; $index < @{$interface->attributes}; $index++) {
    my $attribute = @{$interface->attributes}[$index];
    my $attrType = $attribute->signature->type;
    my $attrName = $attribute->signature->name;
    my $attrExt = $attribute->signature->extendedAttributes;

    my $wrapperRetType = IdlToWrapperType($attrType);
    my $wrapperType = IdlToWrapperType($interfaceName);
    my $wrapperGetter;
    
    if ($attrExt->{'AttributeIsPublic'} || $extensions->{'AttributesArePublic'}) {
      $wrapperGetter = $attrName;
    } else {
      $wrapperGetter = IdlToWrapperAttrGetter($interface, $attribute)."()";
      
    }

    # getter
    if (!$attrExt->{'CustomGetter'}) {
      push(@implContent, <<END);

  v8::Handle<v8::Value> V8${interfaceName}::${attrName}AttrGetter(v8::Local<v8::String> property, const v8::AccessorInfo& info) {
    v8::Local<v8::Object> self = info.Holder();
    struct V8${interfaceName}Private* privData = V8DOM::toClassPtr<V8${interfaceName}Private >(self->GetInternalField(0));
END
      if (IsWrapperType($attrType)) {
        AddToImplIncludes("V8".$attrType.".h");
        push(@implContent, "\n    ".GenerateConditionalUndefReturn($interface, $attribute, "privData->nativeObj->${wrapperGetter}"));
        
        push(@implContent, <<END);

    ${wrapperRetType}* arbaicaRet = new ${wrapperRetType}(privData->nativeObj->${wrapperGetter});

    v8::Handle<v8::Function> arbaicaRetCtor = V8${attrType}::getTmpl()->GetFunction();
    v8::Persistent<v8::Object> arbaicaRetObj = v8::Persistent<v8::Object>::New(arbaicaRetCtor->NewInstance());

    struct V8${attrType}::V8${attrType}Private* retPrivData = new V8${attrType}::V8${attrType}Private();
    retPrivData->dom = privData->dom;
    retPrivData->nativeObj = arbaicaRet;
    
    arbaicaRetObj->SetInternalField(0, V8DOM::toExternal(retPrivData));
    arbaicaRetObj.MakeWeak(0, V8${attrType}::jsDestructor);
    return arbaicaRetObj;
END
      } else {
        my $v8Type = IdlToV8Type($attrType);
        if ($attrType eq "DOMString") {
          if ($attrExt->{'EmptyAsNull'}) {
            push(@implContent, "\n    if (privData->nativeObj->${wrapperGetter}.length() == 0)");
            push(@implContent, "\n      return v8::Undefined();");
          }
          push(@implContent, "\n    return ${v8Type}::New(privData->nativeObj->${wrapperGetter}.c_str());");
        } else {
          push(@implContent, "\n    return ${v8Type}::New(privData->nativeObj->${wrapperGetter});");
        }
      }
      push(@implContent, "\n  }\n");
    }

    if (!$attrExt->{'CustomSetter'}) {
    # setter
      if (!IsReadonly($attribute)) {
        my $wrapperSetter = IdlToWrapperAttrSetter($attrName);
        push(@implContent, "\n  void V8${interfaceName}::${attrName}AttrSetter(v8::Local<v8::String> property, v8::Local<v8::Value> value, const v8::AccessorInfo& info) {");
        push(@implContent, "\n    v8::Local<v8::Object> self = info.Holder();");
        push(@implContent, "\n    struct V8${interfaceName}Private* privData = V8DOM::toClassPtr<V8${interfaceName}Private >(self->GetInternalField(0));");

        my ($handle, $deref) = IdlToArgHandle($attribute->signature->type, "local".ucfirst($attribute->signature->name), "value");

        push(@implContent, "\n    $handle");
        push(@implContent, "\n    privData->nativeObj->${wrapperSetter}(${deref});");
        push(@implContent, "\n  }\n");

      }
    }
  }
}

sub GenerateConditionalUndefReturn
{  
  my $interface = shift;
  my $attribute = shift;
  my $getterExpression = shift;
  
  return "" if ($attribute->signature->type eq "NamedNodeMap");
  return "" if ($attribute->signature->type eq "NodeList");
  return "if (!$getterExpression) return v8::Undefined();";
}

sub GenerateImplementationFunctionCallbacks
{
  my $interface = shift;
  my $interfaceName = $interface->name;
  my $wrapperType = IdlToWrapperType($interfaceName);
  
  # Generate methods for functions.
  foreach my $function (@{$interface->functions}) {
    my $name = $function->signature->name;
    my $attrExt = $function->signature->extendedAttributes;
    my $retType = $function->signature->type;
    my $wrapperRetType = IdlToWrapperType($retType);

    next if ($attrExt->{'Custom'});

    # signature
    push(@implContent, <<END);
  v8::Handle<v8::Value> V8${interfaceName}::${name}Callback(const v8::Arguments& args) {
END

    # arguments count and type checking
    push(@implContent, GenerateArgumentsCountCheck($function, $interface));
    my $argCheckExpr = GenerateArgumentsTypeCheck($function, $interface);

    push(@implContent, <<END) if ($argCheckExpr);
    if (!${argCheckExpr})
      throw V8Exception(\"Parameter mismatch while calling ${name}\");
END

    # get this
    push(@implContent, "\n    v8::Local<v8::Object> self = args.Holder();");
    push(@implContent, "\n    struct V8${interfaceName}Private* privData = V8DOM::toClassPtr<V8${interfaceName}Private >(self->GetInternalField(0));");

    # arguments to local handles
    my $parameterIndex = 0;
    my @argList;
    foreach my $parameter (@{$function->parameters}) {
        my $value = "args[$parameterIndex]";
        my $type = $parameter->type;
        AddToImplIncludes("V8".$type.".h") if (IsWrapperType($type));

        my ($handle, $deref) = IdlToArgHandle($parameter->type, "local".ucfirst($parameter->name), "args[${parameterIndex}]");
        push(@implContent, "\n    ${handle}");
        push(@argList, $deref);

        $parameterIndex++;
    }

    # invoke native function with argument handles
    my $retNativeType = IdlToNativeType($retType);
    my $wrapperFunctionName = IdlToWrapperFunction($interface, $function);
    if (IsWrapperType($retType)) {
      push(@implContent, "\n\n    ${retNativeType}* retVal = new $wrapperRetType(privData->nativeObj->${wrapperFunctionName}(" . join(", ", @argList) . "));\n");
    } elsif ($retNativeType eq "void") {
      push(@implContent, "\n\n    privData->nativeObj->${wrapperFunctionName}(" . join(", ", @argList) . ");\n");
    } else {
      push(@implContent, "\n\n    ${retNativeType} retVal = privData->nativeObj->${wrapperFunctionName}(" . join(", ", @argList) . ");\n");
    }

    # wrap return type if needed
    if (IsWrapperType($retType)) {
      AddToImplIncludes("V8".$retType.".h");

      push(@implContent, <<END);
    v8::Handle<v8::Function> retCtor = V8${retType}::getTmpl()->GetFunction();
    v8::Persistent<v8::Object> retObj = v8::Persistent<v8::Object>::New(retCtor->NewInstance());

    struct V8${retType}::V8${retType}Private* retPrivData = new V8${retType}::V8${retType}Private();
    retPrivData->dom = privData->dom;
    retPrivData->nativeObj = retVal;

    retObj->SetInternalField(0, V8DOM::toExternal(retPrivData));

    retObj.MakeWeak(0, V8${retType}::jsDestructor);
    return retObj;
END
    } else {
      my $toHandleString = NativeToHandle($retNativeType, "retVal");
      push(@implContent, "\n    return ${toHandleString};");
    }

    push(@implContent, "\n  }\n\n");
  }

}

sub GenerateImplementation
{
    my $object = shift;
    my $interface = shift;
    my $interfaceName = $interface->name;
    my $visibleInterfaceName = $codeGenerator->GetVisibleInterfaceName($interface);
    my $v8InterfaceName = "V8$interfaceName";
    my $wrapperType = IdlToWrapperType($interfaceName);

    AddToImplIncludes("V8${interfaceName}.h");
    
    # Find the super descriptor.
    my $parentClass = "";
    my $parentClassTemplate = "";
    foreach (@{$interface->parents}) {
        my $parent = $_;
        AddToImplIncludes("V8${parent}.h");
        $parentClass = "V8" . $parent;
        last;
    }
    push(@implContent, "namespace Arabica {\n");
    push(@implContent, "namespace DOM {\n\n");
    push(@implContent, "  v8::Persistent<v8::FunctionTemplate> V8${interfaceName}::Tmpl;\n\n");

    GenerateImplementationAttributes($interface);
    GenerateImplementationFunctionCallbacks($interface);

    push(@implContent, <<END);
  bool V8${interfaceName}::hasInstance(v8::Handle<v8::Value> value) {
    return getTmpl()->HasInstance(value);
  }

} 
} 
END

    # We've already added the header for this file in implContentHeader, so remove
    # it from implIncludes to ensure we don't #include it twice.
#    delete $implIncludes{"${v8InterfaceName}.h"};
}

sub WriteData
{
    my $object = shift;
    my $interface = shift;
    my $outputDir = shift;
    my $outputHeadersDir = shift;

    my $name = $interface->name;
    my $prefix = FileNamePrefix;
    my $headerFileName = "$outputHeadersDir/$prefix$name.h";
    my $implFileName = "$outputDir/$prefix$name.cpp";

    # print "WriteData\n";
    # print Dumper($interface);
    # exit();

    # Update a .cpp file if the contents are changed.
    my $contents = join "", @implContentHeader;

    my @includes = ();
    my %implIncludeConditions = ();
    foreach my $include (keys %implIncludes) {
        my $condition = $implIncludes{$include};
        my $checkType = $include;
        $checkType =~ s/\.h//;
        next if $codeGenerator->IsSVGAnimatedType($checkType);

        if ($include =~ /wtf/) {
            $include = "\<$include\>";
        } else {
            $include = "\"$include\"";
        }

        if ($condition eq 1) {
            push @includes, $include;
        } else {
            push @{$implIncludeConditions{$condition}}, $include;
        }
    }
    foreach my $include (sort @includes) {
        $contents .= "#include $include\n";
    }
    foreach my $condition (sort keys %implIncludeConditions) {
        $contents .= "\n#if " . $codeGenerator->GenerateConditionalStringFromAttributeValue($condition) . "\n";
        foreach my $include (sort @{$implIncludeConditions{$condition}}) {
            $contents .= "#include $include\n";
        }
        $contents .= "#endif\n";
    }

    $contents .= "\n";
    $contents .= join "", @implContentDecls, @implContent;
    $codeGenerator->UpdateFile($implFileName, $contents);

    %implIncludes = ();
    @implContentHeader = ();
    @implContentDecls = ();
    @implContent = ();

    # Update a .h file if the contents are changed.
    $contents = join "", @headerContent;
    $codeGenerator->UpdateFile($headerFileName, $contents);

    @headerContent = ();
}

sub IdlToV8Type
{
  my $idlType = shift;
  return "v8::Integer" if ($idlType eq "unsigned short");
  return "v8::Integer" if ($idlType eq "short");
  return "v8::Integer" if ($idlType eq "unsigned long");
  return "v8::Integer" if ($idlType eq "long");
  return "v8::String" if ($idlType eq "DOMString");
  return "v8::Boolean" if ($idlType eq "boolean");
  return "v8::Number" if ($idlType eq "double");
  die($idlType);
}

sub IdlToNativeType
{
  my $idlType = shift;
  
  return IdlToWrapperType($idlType) if (IsWrapperType($idlType));

  return "std::string" if ($idlType eq "DOMString");
  return "bool" if ($idlType eq "boolean");
  return "void" if ($idlType eq "void");
  return "double" if ($idlType eq "double");
  die(${idlType});
}

sub NativeToHandle
{
  my $nativeType  = shift;
  my $nativeName  = shift;
  
  return ("v8::Boolean::New(${nativeName})") if ($nativeType eq "bool");
  return ("v8::Number::New(${nativeName})") if ($nativeType eq "double");
  return ("v8::String::New(${nativeName}.c_str())") if ($nativeType eq "std::string");
  return ("v8::Undefined()") if ($nativeType eq "void");
  
  die($nativeType);
}

sub IdlToWrapperType
{
  my $idlType = shift;
  return "Arabica::XPath::XPathValue<std::string>" if ($idlType eq "XPathResult");
  return "Arabica::XPath::NodeSet<std::string>" if ($idlType eq "NodeSet");
  return "Arabica::DOM::Node<std::string>" if ($idlType eq "Node");
  return "Arabica::DOM::Element<std::string>" if ($idlType eq "Element");
  return "uscxml::Event" if ($idlType eq "SCXMLEvent");
  return "uscxml::Storage" if ($idlType eq "Storage");
  return "Arabica::DOM::${idlType}<std::string>";
}

sub IdlToArgHandle
{
  my $type = shift;
  my $localName = shift;
  my $paramName = shift;
  
  return ("v8::String::AsciiValue ${localName}(${paramName});", "*${localName}") if ($type eq "DOMString");
  return ("unsigned long ${localName} = ${paramName}->ToNumber()->Uint32Value();", ${localName}) if ($type eq "unsigned long");
  return ("unsigned short ${localName} = ${paramName}->ToNumber()->Uint32Value();", ${localName}) if ($type eq "unsigned short");
  return ("bool ${localName} = ${paramName}->ToBoolean()->BooleanValue();", ${localName}) if ($type eq "boolean");
  
  if (IsWrapperType($type)) {
    my $wrapperType = IdlToWrapperType($type);
    return ("${wrapperType}* ${localName} = V8DOM::toClassPtr<V8${type}::V8${type}Private >(${paramName}->ToObject()->GetInternalField(0))->nativeObj;", "*${localName}");
  }

  print $type."\n";
  die();
}

sub IdlToWrapperAttrGetter
{
  my $interface = shift;
  my $attribute = shift;
    
  return $attribute->signature->name if ($interface->name eq "NodeSet" && $attribute->signature->name eq "size");
  return $attribute->signature->name if ($interface->name eq "NodeSet" && $attribute->signature->name eq "empty");
  return "asString" if ($interface->name eq "XPathResult" && $attribute->signature->name eq "stringValue");
  return "asBool" if ($interface->name eq "XPathResult" && $attribute->signature->name eq "booleanValue");
  return "asNumber" if ($interface->name eq "XPathResult" && $attribute->signature->name eq "numberValue");
  
  return "get" . ucfirst($attribute->signature->name);
}

sub IdlToWrapperFunction
{
  my $interface = shift;
  my $function = shift;
  
  # if ($interface->name eq "NodeSet" && $function->signature->name eq "toDocumentOrder") {
  #   print Dumper($interface);
  #   print Dumper($function);
  # }
  
  return "to_document_order" if ($interface->name eq "NodeSet" && $function->signature->name eq "toDocumentOrder");

  return $function->signature->name;
  
}

sub IdlToWrapperAttrSetter
{
  my $idlAttr = shift;
  return "set" . ucfirst($idlAttr);
}


sub IsReadonly
{
    my $attribute = shift;
    my $attrExt = $attribute->signature->extendedAttributes;
    return ($attribute->type =~ /readonly/ || $attrExt->{"V8ReadOnly"}) && !$attrExt->{"Replaceable"};
}


sub GenerateArgumentsCountCheck
{
    my $function = shift;
    my $interface = shift;

    my $numMandatoryParams = 0;
    my $allowNonOptional = 1;
    foreach my $param (@{$function->parameters}) {
        if ($param->extendedAttributes->{"Optional"} or $param->isVariadic) {
            $allowNonOptional = 0;
        } else {
            die "An argument must not be declared to be optional unless all subsequent arguments to the operation are also optional." if !$allowNonOptional;
            $numMandatoryParams++;
        }
    }

    my $argumentsCountCheckString = "";
    if ($numMandatoryParams >= 1) {
        $argumentsCountCheckString .= "    if (args.Length() < $numMandatoryParams)\n";
        $argumentsCountCheckString .= "        throw V8Exception(\"Wrong number of arguments in " . $function->signature->name . "\");\n";
    }
    return $argumentsCountCheckString;
}

sub GenerateArgumentsTypeCheck
{
    my $function = shift;
    my $interface = shift;

    my @andExpression = ();

    my $parameterIndex = 0;
    foreach my $parameter (@{$function->parameters}) {
        my $value = "args[$parameterIndex]";
        my $type = $parameter->type;

        # Only DOMString or wrapper types are checked.
        # For DOMString with StrictTypeChecking only Null, Undefined and Object
        # are accepted for compatibility. Otherwise, no restrictions are made to
        # match the non-overloaded behavior.
        # FIXME: Implement WebIDL overload resolution algorithm.
        if ($codeGenerator->IsStringType($type)) {
            if ($parameter->extendedAttributes->{"StrictTypeChecking"}) {
                push(@andExpression, "(${value}->IsNull() || ${value}->IsUndefined() || ${value}->IsString() || ${value}->IsObject())");
            }
        } elsif ($parameter->extendedAttributes->{"Callback"}) {
            # For Callbacks only checks if the value is null or object.
            push(@andExpression, "(${value}->IsNull() || ${value}->IsFunction())");
        } elsif ($codeGenerator->IsArrayType($type) || $codeGenerator->GetSequenceType($type)) {
            if ($parameter->isNullable) {
                push(@andExpression, "(${value}->IsNull() || ${value}->IsArray())");
            } else {
                push(@andExpression, "(${value}->IsArray())");
            }
        } elsif (IsWrapperType($type)) {
            if ($parameter->isNullable) {
                push(@andExpression, "(${value}->IsNull() || V8${type}::hasInstance($value))");
            } else {
                push(@andExpression, "(V8${type}::hasInstance($value))");
            }
        }

        $parameterIndex++;
    }
    my $res = join(" && ", @andExpression);
    $res = "($res)" if @andExpression > 1;
    return $res;
}


my %non_wrapper_types = (
    'CompareHow' => 1,
    'DOMObject' => 1,
    'DOMString' => 1,
    'DOMString[]' => 1,
    'DOMTimeStamp' => 1,
    'Date' => 1,
    'Dictionary' => 1,
    'EventListener' => 1,
    # FIXME: When EventTarget is an interface and not a mixin, fix this so that
    # EventTarget is treated as a wrapper type.
    'EventTarget' => 1,
    'IDBKey' => 1,
    'JSObject' => 1,
    'MediaQueryListListener' => 1,
    'NodeFilter' => 1,
    'SerializedScriptValue' => 1,
    'any' => 1,
    'boolean' => 1,
    'double' => 1,
    'float' => 1,
    'int' => 1,
    'long long' => 1,
    'long' => 1,
    'short' => 1,
    'void' => 1,
    'unsigned int' => 1,
    'unsigned long long' => 1,
    'unsigned long' => 1,
    'unsigned short' => 1
);

sub IsWrapperType
{
    my $type = shift;
    return !($non_wrapper_types{$type});
}

sub GenerateHeaderContentHeader
{
    my $interface = shift;
    my $v8InterfaceName = "V8" . $interface->name;
    my $conditionalString = $codeGenerator->GenerateConditionalString($interface);

    my @headerContentHeader = split("\r", $headerTemplate);

    push(@headerContentHeader, "\n#if ${conditionalString}\n") if $conditionalString;
    push(@headerContentHeader, "\n#ifndef ${v8InterfaceName}" . "_h");
    push(@headerContentHeader, "\n#define ${v8InterfaceName}" . "_h\n\n");
    return @headerContentHeader;
}

1;
