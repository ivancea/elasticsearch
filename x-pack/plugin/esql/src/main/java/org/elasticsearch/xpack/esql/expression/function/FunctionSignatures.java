/*
 * Copyright Elasticsearch B.V. and/or licensed to Elasticsearch B.V. under one
 * or more contributor license agreements. Licensed under the Elastic License
 * 2.0; you may not use this file except in compliance with the Elastic License
 * 2.0.
 */

package org.elasticsearch.xpack.esql.expression.function;

import org.elasticsearch.xpack.esql.core.type.DataType;

import java.util.ArrayList;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Locale;
import java.util.Set;

/**
 * Reads and expands {@link FunctionInfo#signatures()} into concrete type tuples.
 * <p>
 *     Parameter entries may use {@code |} for unions and {@link TypeGroup} names
 *     (e.g. {@code NUMERIC}, {@code STRING}, {@code GEO}, {@code SORTABLE}, {@code ALL}).
 *     {@link Signature#returnType()} must be a single concrete type name — groups are
 *     not allowed there (a signature returns one type; use a future {@code $N} reference
 *     when the return type should track a parameter).
 * </p>
 */
public final class FunctionSignatures {
    private FunctionSignatures() {}

    /**
     * A fully expanded signature: one concrete type per argument, plus return type.
     */
    public record ConcreteSignature(List<DataType> argTypes, DataType returnType) {}

    /**
     * Declared signatures for {@code def}, or an empty set when the function has not
     * opted into {@link FunctionInfo#signatures()}.
     */
    public static Set<ConcreteSignature> declaredSignatures(FunctionDefinition def) {
        FunctionInfo info = EsqlFunctionRegistry.functionInfo(def);
        if (info == null || info.signatures().length == 0) {
            return Set.of();
        }
        return expand(info.signatures());
    }

    /**
     * Expands each {@link Signature} into concrete signatures.
     */
    public static Set<ConcreteSignature> expand(Signature[] signatures) {
        Set<ConcreteSignature> result = new LinkedHashSet<>();
        for (Signature signature : signatures) {
            result.addAll(expandOne(signature));
        }
        return result;
    }

    private static List<ConcreteSignature> expandOne(Signature signature) {
        if (TypeGroup.parse(signature.returnType()) != null) {
            throw new IllegalArgumentException(
                "return type ["
                    + signature.returnType()
                    + "] must be a concrete type, not a type group; a signature returns a single type"
            );
        }

        List<List<DataType>> perPosition = new ArrayList<>(signature.params().length);
        for (String param : signature.params()) {
            perPosition.add(resolveParam(param));
        }

        DataType returnType = DataType.fromNameOrAlias(signature.returnType());
        List<ConcreteSignature> expanded = new ArrayList<>();
        expandRecursive(perPosition, 0, new ArrayList<>(perPosition.size()), returnType, expanded);
        return expanded;
    }

    private static List<DataType> resolveParam(String param) {
        List<DataType> types = new ArrayList<>();
        for (String part : param.split("\\|")) {
            String trimmed = part.trim();
            if (trimmed.isEmpty()) {
                throw new IllegalArgumentException("empty type in signature param [" + param + "]");
            }
            types.addAll(resolveToken(trimmed));
        }
        return types;
    }

    private static List<DataType> resolveToken(String token) {
        TypeGroup group = TypeGroup.parse(token);
        if (group != null) {
            return group.types();
        }
        return List.of(DataType.fromNameOrAlias(token.toLowerCase(Locale.ROOT)));
    }

    private static void expandRecursive(
        List<List<DataType>> perPosition,
        int index,
        List<DataType> current,
        DataType returnType,
        List<ConcreteSignature> out
    ) {
        if (index == perPosition.size()) {
            out.add(new ConcreteSignature(List.copyOf(current), returnType));
            return;
        }
        for (DataType type : perPosition.get(index)) {
            current.add(type);
            expandRecursive(perPosition, index + 1, current, returnType, out);
            current.remove(current.size() - 1);
        }
    }
}
