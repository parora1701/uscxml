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

package CodeGeneratorArabicaJSC;

use strict;
use Data::Dumper;
use Carp qw/longmess cluck confess/;

use constant FileNamePrefix => "JSC";

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

    if ($header eq "JSCbool.h") {
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

    $headerIncludes{"uscxml/plugins/datamodel/ecmascript/JavaScriptCore/JSCDOM.h"} = 1;
    $headerIncludes{"DOM/Node.hpp"} = 1;
    $headerIncludes{"JavaScriptCore/JavaScriptCore.h"} = 1;

    foreach (@{$interface->parents}) {
        my $parent = $_;
        $headerIncludes{"JSC${parent}.h"} = 1;
    }

    push(@headerContent, "#include \<string\>\n");
    foreach my $headerInclude (sort keys(%headerIncludes)) {
        if ($headerInclude =~ /wtf|JavaScriptCore\/JavaScriptCore\.h/) {
            push(@headerContent, "#include \<${headerInclude}\>\n");
        } else {
            push(@headerContent, "#include \"${headerInclude}\"\n");
        }
    }

    push(@headerContent, "");
    push(@headerContent, "\nnamespace Arabica {");
    push(@headerContent, "\nnamespace DOM {\n");

    push(@headerContent, "\nclass JSC${interfaceName} {");
    push(@headerContent, "\npublic:");

    my $wrapperType = IdlToWrapperType($interfaceName);
    push(@headerContent, <<END);

	struct JSC${interfaceName}Private {
		JSCDOM* dom;
		${wrapperType}* nativeObj;
	};
END

    if ($extensions->{'DontDestroyWrapped'}) {
      push(@headerContent, "\n	JSC_DESTRUCTOR_KEEP_WRAPPED(JSC${interfaceName}Private);");
    } else {
      push(@headerContent, "\n	JSC_DESTRUCTOR(JSC${interfaceName}Private);");
    }
    push(@headerContent, "\n");


    # callbacks for actual functions
    foreach my $function (@{$interface->functions}) {
        my $name = $function->signature->name;
        my $attrExt = $function->signature->extendedAttributes;
        my $custom = ($attrExt->{'Custom'} ? "Custom" : "");
        push(@headerContent, "\n  static JSValueRef ${name}${custom}Callback(JSContextRef ctx, JSObjectRef function, JSObjectRef thisObj, size_t argumentCount, const JSValueRef* arguments, JSValueRef* exception);");
    }
    push(@headerContent, "\n");

    # attribute getter and setters
    foreach my $attribute (@{$interface->attributes}) {
        my $name = $attribute->signature->name;
        my $attrExt = $attribute->signature->extendedAttributes;
        my $customGetter = ($attrExt->{'CustomGetter'} ? "Custom" : "");
        my $customSetter = ($attrExt->{'CustomSetter'} ? "Custom" : "");
        push(@headerContent, "\n  static JSValueRef ${name}${customGetter}AttrGetter(JSContextRef ctx, JSObjectRef thisObj, JSStringRef propertyName, JSValueRef* exception);");
        if (!IsReadonly($attribute)) {
          push(@headerContent, "\n  static bool ${name}${customSetter}AttrSetter(JSContextRef ctx, JSObjectRef thisObj, JSStringRef propertyName, JSValueRef value, JSValueRef* exception);");
        }
    }

		# const getters
	  foreach my $constant (@{$interface->constants}) {
	    my $name = $constant->name;
	    my $value = $constant->value;
	    my $getter = "${name}ConstGetter";
      push(@headerContent, "\n  static JSValueRef ${getter}(JSContextRef ctx, JSObjectRef thisObj, JSStringRef propertyName, JSValueRef* exception);");
	  }

    if ($extensions->{'CustomIndexedGetter'}) {
      push(@headerContent, "\n    static bool hasPropertyCustomCallback(JSContextRef ctx, JSObjectRef object, JSStringRef propertyName);");
      push(@headerContent, "\n    static JSValueRef getPropertyCustomCallback(JSContextRef ctx, JSObjectRef object, JSStringRef propertyName, JSValueRef* exception);");
    }
    if ($extensions->{'CustomIndexedSetter'}) {
      push(@headerContent, "\n    static JSValueRef setPropertyCustomCallback(JSContextRef ctx, JSObjectRef object, JSStringRef propertyName, JSValueRef value, JSValueRef* exception);");
    }
    push(@headerContent, "\n");

    push(@headerContent, <<END);


	static JSStaticValue staticValues[];
	static JSStaticFunction staticFunctions[];

	static JSClassRef Tmpl;
	static JSClassRef getTmpl() {
  	if (Tmpl == NULL) {
  		JSClassDefinition classDef = kJSClassDefinitionEmpty;
  		classDef.staticValues = staticValues;
  		classDef.staticFunctions = staticFunctions;
  		classDef.finalize = jsDestructor;
END
			if ($extensions->{'CustomIndexedGetter'}) {
				push(@headerContent, "		classDef.hasProperty = hasPropertyCustomCallback;\n");
				push(@headerContent, "		classDef.getProperty = getPropertyCustomCallback;\n");
			}
			if ($extensions->{'CustomIndexedSetter'}) {
				push(@headerContent, "		classDef.setProperty = setPropertyCustomCallback;\n");
			}
		  if (@{$interface->parents}) {
		    my $parent = @{$interface->parents}[0];
		    push(@headerContent, "		classDef.parentClass = JSC${parent}::getTmpl();\n");
		  }

	    push(@headerContent, <<END);

  		Tmpl = JSClassCreate(&classDef);
  		JSClassRetain(Tmpl);
  	}
  	return Tmpl;
  }

END

    push(@headerContent, "\n};\n\n}\n}\n\n");
    push(@headerContent, "#endif // JSC${interfaceName}" . "_h\n");

}

#
# Write class template prototype constructor
#
sub GenerateClassDefStatics
{
  my $interface = shift;
  my $interfaceName = $interface->name;
  my $extensions = $interface->extendedAttributes;

  push(@implContent, "\nJSStaticValue JSC${interfaceName}::staticValues[] = {");
  foreach my $attribute (@{$interface->attributes}) {
    my $name = $attribute->signature->name;
    my $attrExt = $attribute->signature->extendedAttributes;
    my $customGetter = ($attrExt->{'CustomGetter'} ? "Custom" : "");
    my $customSetter = ($attrExt->{'CustomSetter'} ? "Custom" : "");
    my $getter = "${name}${customGetter}AttrGetter";
    my $setter = (IsReadonly($attribute) ? "0" : "${name}${customSetter}AttrSetter");
    my $flags = "kJSPropertyAttributeDontDelete";
    $flags .= " | kJSPropertyAttributeReadOnly" if (IsReadonly($attribute));
    push(@implContent, "\n  { \"${name}\", ${getter}, ${setter}, ${flags} },");
  
  }  

  push(@implContent, "\n");
  foreach my $constant (@{$interface->constants}) {
    my $name = $constant->name;
    my $value = $constant->value;
    my $getter = "${name}ConstGetter";
    my $flags = "kJSPropertyAttributeDontDelete | kJSPropertyAttributeReadOnly";
    push(@implContent, "\n  { \"${name}\", ${getter}, 0, ${flags} },");
  }

  push(@implContent, "\n	{ 0, 0, 0, 0 }");
  push(@implContent, "\n};\n");

  push(@implContent, "\nJSStaticFunction JSC${interfaceName}::staticFunctions[] = {");
  foreach my $function (@{$interface->functions}) {
    my $name = $function->signature->name;
    my $attrExt = $function->signature->extendedAttributes;
    my $custom = ($attrExt->{'Custom'} ? "Custom" : "");
    my $callback = ${name}.${custom}."Callback";
    my $flags = "kJSPropertyAttributeDontDelete";
    push(@implContent, "\n  { \"${name}\", ${callback}, ${flags} },");
    
  }
  push(@implContent, "\n	{ 0, 0, 0 }");
  push(@implContent, "\n};\n");

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

  JSValueRef JSC${interfaceName}::${attrName}AttrGetter(JSContextRef ctx, JSObjectRef object, JSStringRef propertyName, JSValueRef *exception) {
    struct JSC${interfaceName}Private* privData = (struct JSC${interfaceName}Private*)JSObjectGetPrivate(object);
END
      if (IsWrapperType($attrType)) {
        AddToImplIncludes("JSC".$attrType.".h");
        push(@implContent, "\n    ".GenerateConditionalUndefReturn($interface, $attribute, "privData->nativeObj->${wrapperGetter}"));
        
        push(@implContent, <<END);

    ${wrapperRetType}* arabicaRet = new ${wrapperRetType}(privData->nativeObj->${wrapperGetter});

		JSClassRef arbaicaRetClass = JSC${attrType}::getTmpl();

		struct JSC${attrType}::JSC${attrType}Private* retPrivData = new JSC${attrType}::JSC${attrType}Private();
		retPrivData->dom = privData->dom;
		retPrivData->nativeObj = arabicaRet;

		JSObjectRef arbaicaRetObj = JSObjectMake(ctx, arbaicaRetClass, arabicaRet);
    return arbaicaRetObj;
END
      } else {
        my $JSCType = IdlToJSCType($attrType);
        if ($JSCType eq "String") {
          if ($attrExt->{'EmptyAsNull'}) {
            push(@implContent, "\n    if (privData->nativeObj->${wrapperGetter}.length() == 0)");
            push(@implContent, "\n      return JSValueMakeUndefined(ctx);");
          }
          push(@implContent, <<END);

		JSStringRef stringRef = JSStringCreateWithUTF8CString(privData->nativeObj->${wrapperGetter}.c_str());
		JSValueRef retVal = JSValueMakeString(ctx, stringRef);
		JSStringRelease(stringRef);
		return retVal;
END
        } elsif($JSCType eq "Number") {
          push(@implContent, "\n    return JSValueMakeNumber(ctx, privData->nativeObj->${wrapperGetter});\n");
        } elsif($JSCType eq "Boolean") {
          push(@implContent, "\n    return JSValueMakeBoolean(ctx, privData->nativeObj->${wrapperGetter});\n");
        }
      }
      push(@implContent, "  }\n\n");
    }

    if (!$attrExt->{'CustomSetter'}) {
    # setter
      if (!IsReadonly($attribute)) {
        push(@implContent, "\n  bool JSC${interfaceName}::${attrName}AttrSetter(JSContextRef ctx, JSObjectRef thisObj, JSStringRef propertyName, JSValueRef value, JSValueRef* exception) {");
        push(@implContent, "\n    struct JSC${interfaceName}Private* privData = (struct JSC${interfaceName}Private*)JSObjectGetPrivate(thisObj);\n");
        my $wrapperSetter = IdlToWrapperAttrSetter($attrName);

        my ($handle, $deref) = IdlToArgHandle($attribute->signature->type, "local".ucfirst($attribute->signature->name), "value");

        push(@implContent, "\n    $handle");
        push(@implContent, "\n    privData->nativeObj->${wrapperSetter}(${deref});");
        push(@implContent, "\n    return true;");
        push(@implContent, "\n  }\n");

      }
    }
  }
  foreach my $constant (@{$interface->constants}) {
    my $name = $constant->name;
    my $value = $constant->value;
    my $getter = "${name}ConstGetter";
		push(@implContent, "	JSValueRef JSC${interfaceName}::${getter}(JSContextRef ctx, JSObjectRef thisObj, JSStringRef propertyName, JSValueRef *exception) {");
		my $JSCType = IdlToJSCType($constant->type);
		if ($JSCType eq "String") {
			push(@implContent,
			"\n		JSStringRef jscString = JSStringCreateWithUTF8CString(" . $constant->value . ");".
			"\n		JSValueRef retVal = JSValueMakeString(ctx, jscString);".
			"\n		JSStringRelease(jscString);".
			"\n		return retVal;\n");
		} elsif($JSCType eq "Number") {
			push(@implContent, "\n		return JSValueMakeNumber(ctx, " . $constant->value . ");\n");
		} elsif($JSCType eq "Boolean") {
			push(@implContent, "\n		return JSValueMakeBoolean(ctx, " . $constant->value . ");\n");
		}
		push(@implContent, <<END);
	}

END

  }

}

sub GenerateConditionalUndefReturn
{  
  my $interface = shift;
  my $attribute = shift;
  my $getterExpression = shift;
  
  return "" if ($attribute->signature->type eq "NamedNodeMap");
  return "" if ($attribute->signature->type eq "NodeList");
  return "if (!$getterExpression) return JSValueMakeUndefined(ctx);";
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
	JSValueRef JSC${interfaceName}::${name}Callback(JSContextRef ctx, JSObjectRef function, JSObjectRef thisObj, size_t argumentCount, const JSValueRef* arguments, JSValueRef* exception) {
END

    # arguments count and type checking
    push(@implContent, GenerateArgumentsCountCheck($function, $interface));
    my $argCheckExpr = GenerateArgumentsTypeCheck($function, $interface);

    # get this
    push(@implContent, "\n    struct JSC${interfaceName}Private* privData = (struct JSC${interfaceName}Private*)JSObjectGetPrivate(thisObj);\n");

    # arguments to local handles
    my $parameterIndex = 0;
    my @argList;
    foreach my $parameter (@{$function->parameters}) {
        my $type = $parameter->type;
        AddToImplIncludes("JSC".$type.".h") if (IsWrapperType($type));

        my ($handle, $deref) = IdlToArgHandle($parameter->type, "local".ucfirst($parameter->name), "arguments[${parameterIndex}]");
        push(@implContent, "\n    ${handle}");
#        push(@implContent, "\n    if (exception)\n      return JSValueMakeUndefined(ctx);");
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
      AddToImplIncludes("JSC".$retType.".h");

      push(@implContent, <<END);
		JSClassRef retClass = JSC${retType}::getTmpl();

		struct JSC${retType}::JSC${retType}Private* retPrivData = new JSC${retType}::JSC${retType}Private();
		retPrivData->dom = privData->dom;
		retPrivData->nativeObj = retVal;

		JSObjectRef retObj = JSObjectMake(ctx, retClass, retPrivData);

    return retObj;
END
    } else {
      my $toHandleString = NativeToHandle($retNativeType, "retVal", "jscRetVal");
      push(@implContent, "${toHandleString}\n    return jscRetVal;");
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
    my $JSCInterfaceName = "JSC$interfaceName";
    my $wrapperType = IdlToWrapperType($interfaceName);

    AddToImplIncludes("JSC${interfaceName}.h");
    
    # Find the super descriptor.
    my $parentClass = "";
    my $parentClassTemplate = "";
    foreach (@{$interface->parents}) {
        my $parent = $_;
        AddToImplIncludes("JSC${parent}.h");
        $parentClass = "JSC" . $parent;
        last;
    }
    push(@implContent, "namespace Arabica {\n");
    push(@implContent, "namespace DOM {\n\n");
    push(@implContent, "JSClassRef JSC${interfaceName}::Tmpl;\n");

    GenerateClassDefStatics($interface);
    GenerateImplementationAttributes($interface);
    GenerateImplementationFunctionCallbacks($interface);

    push(@implContent, <<END);

} 
} 
END

    # We've already added the header for this file in implContentHeader, so remove
    # it from implIncludes to ensure we don't #include it twice.
#    delete $implIncludes{"${JSCInterfaceName}.h"};
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

sub IdlToJSCType
{
  my $idlType = shift;
  return "Number" if ($idlType eq "unsigned short");
  return "Number" if ($idlType eq "short");
  return "Number" if ($idlType eq "unsigned long");
  return "Number" if ($idlType eq "long");
  return "String" if ($idlType eq "DOMString");
  return "Boolean" if ($idlType eq "boolean");
  return "Number" if ($idlType eq "double");
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
  my $paramName = shift;
  
  return ("\n		JSValueRef ${paramName} = JSValueMakeBoolean(ctx, ${nativeName});") if ($nativeType eq "bool");
  return ("\n		JSValueRef ${paramName} = JSValueMakeNumber(ctx, ${nativeName});") if ($nativeType eq "double");
  return ("\n		JSValueRef ${paramName} = JSValueMakeUndefined(ctx);") if ($nativeType eq "void");
  return (
		"\n		JSStringRef jscString = JSStringCreateWithUTF8CString(${nativeName}.c_str());".
		"\n		JSValueRef ${paramName} = JSValueMakeString(ctx, jscString);".
		"\n		JSStringRelease(jscString);"
	) if ($nativeType eq "std::string");
  
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
	if ($type eq "DOMString") {
  	return (
			"JSStringRef stringRef${localName} = JSValueToStringCopy(ctx, ${paramName}, exception);\n" .
			"\t\tsize_t ${localName}MaxSize = JSStringGetMaximumUTF8CStringSize(stringRef${localName});\n" .
			"\t\tchar* ${localName}Buffer = new char[${localName}MaxSize];\n" .
			"\t\tJSStringGetUTF8CString(stringRef${localName}, ${localName}Buffer, ${localName}MaxSize);\n" .
			"\t\tstd::string ${localName}(${localName}Buffer);\n" .
			"\t\tJSStringRelease(stringRef${localName});\n" .
			"\t\tfree(${localName}Buffer);\n", 
			"${localName}") ;
	}
  return ("unsigned long ${localName} = (unsigned long)JSValueToNumber(ctx, ${paramName}, exception);", ${localName}) if ($type eq "unsigned long");
  return ("unsigned short ${localName} = (unsigned short)JSValueToNumber(ctx, ${paramName}, exception);", ${localName}) if ($type eq "unsigned short");
  return ("bool ${localName} = JSValueToBoolean(ctx, ${paramName});", ${localName}) if ($type eq "boolean");
  
  if (IsWrapperType($type)) {
    my $wrapperType = IdlToWrapperType($type);
    return ("${wrapperType}* ${localName} = ((struct JSC${type}::JSC${type}Private*)JSObjectGetPrivate(JSValueToObject(ctx, ${paramName}, exception)))->nativeObj;", "*${localName}");
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
    return ($attribute->type =~ /readonly/ || $attrExt->{"JSCReadOnly"}) && !$attrExt->{"Replaceable"};
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
        $argumentsCountCheckString .= 
"    if (argumentCount < $numMandatoryParams) {\n".
"      std::string errorMsg = \"Wrong number of arguments in " . $function->signature->name . "\";\n" .
"      JSStringRef string = JSStringCreateWithUTF8CString(errorMsg.c_str());\n".
"      JSValueRef exceptionString =JSValueMakeString(ctx, string);\n".
"      JSStringRelease(string);\n".
"      *exception = JSValueToObject(ctx, exceptionString, NULL);\n".
"      return NULL;\n".
"    }\n";
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
                push(@andExpression, "(${value}->IsNull() || JSC${type}::hasInstance($value))");
            } else {
                push(@andExpression, "(JSC${type}::hasInstance($value))");
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
    my $JSCInterfaceName = "JSC" . $interface->name;
    my $conditionalString = $codeGenerator->GenerateConditionalString($interface);

    my @headerContentHeader = split("\r", $headerTemplate);

    push(@headerContentHeader, "\n#if ${conditionalString}\n") if $conditionalString;
    push(@headerContentHeader, "\n#ifndef ${JSCInterfaceName}" . "_h");
    push(@headerContentHeader, "\n#define ${JSCInterfaceName}" . "_h\n\n");
    return @headerContentHeader;
}

1;
