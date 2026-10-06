/*
 * Copyright Elasticsearch B.V. and/or licensed to Elasticsearch B.V. under one
 * or more contributor license agreements. Licensed under the Elastic License
 * 2.0; you may not use this file except in compliance with the Elastic License
 * 2.0.
 */

package org.elasticsearch.xpack.esql.expression.function.scalar.conditional;

import org.elasticsearch.common.io.stream.StreamOutput;
import org.elasticsearch.compute.expression.ExpressionEvaluator;
import org.elasticsearch.xpack.esql.core.expression.Expression;
import org.elasticsearch.xpack.esql.core.expression.Literal;
import org.elasticsearch.xpack.esql.core.tree.NodeInfo;
import org.elasticsearch.xpack.esql.core.tree.Source;
import org.elasticsearch.xpack.esql.core.type.DataType;
import org.elasticsearch.xpack.esql.expression.OnlySurrogateExpression;
import org.elasticsearch.xpack.esql.expression.function.FunctionAppliesTo;
import org.elasticsearch.xpack.esql.expression.function.FunctionAppliesToLifecycle;
import org.elasticsearch.xpack.esql.expression.function.FunctionDefinition;
import org.elasticsearch.xpack.esql.expression.function.FunctionInfo;
import org.elasticsearch.xpack.esql.expression.function.Param;
import org.elasticsearch.xpack.esql.expression.function.scalar.EsqlScalarFunction;

import java.io.IOException;
import java.util.List;

/**
 * Prototype sugar for dashboard breakdown controls: {@code FIELD_OR(??field, fallback)} is {@code field}, or
 * {@code fallback} when the {@code ??field} parameter is {@code null}. The parser only accepts a {@code null}
 * {@code ??} parameter as the first argument of this function, where it arrives as a {@code null} literal.
 */
public class FieldOr extends EsqlScalarFunction implements OnlySurrogateExpression {
    public static final FunctionDefinition DEFINITION = FunctionDefinition.def(FieldOr.class).binary(FieldOr::new).name("field_or");

    private final Expression field;
    private final Expression fallback;

    @FunctionInfo(
        returnType = { "boolean", "date", "double", "integer", "ip", "keyword", "long", "text" },
        description = "Returns `field`, or `fallback` when the `??field` parameter is `null`.",
        preview = true,
        appliesTo = { @FunctionAppliesTo(lifeCycle = FunctionAppliesToLifecycle.PREVIEW, version = "9.6.0") }
    )
    public FieldOr(
        Source source,
        @Param(
            name = "field",
            type = { "boolean", "date", "double", "integer", "ip", "keyword", "long", "text" },
            description = "A `??field` parameter."
        ) Expression field,
        @Param(
            name = "fallback",
            type = { "boolean", "date", "double", "integer", "ip", "keyword", "long", "text" },
            description = "Value used when the parameter is `null`."
        ) Expression fallback
    ) {
        super(source, List.of(field, fallback));
        this.field = field;
        this.fallback = fallback;
    }

    @Override
    public String getWriteableName() {
        throw new UnsupportedOperationException("FieldOr does not support serialization.");
    }

    @Override
    public void writeTo(StreamOutput out) throws IOException {
        throw new UnsupportedOperationException("FieldOr does not support serialization.");
    }

    @Override
    protected TypeResolution resolveType() {
        return childrenResolved() ? TypeResolution.TYPE_RESOLVED : new TypeResolution("Unresolved children");
    }

    @Override
    public DataType dataType() {
        return unset() ? fallback.dataType() : field.dataType();
    }

    @Override
    public boolean foldable() {
        return false;
    }

    @Override
    public Expression replaceChildren(List<Expression> newChildren) {
        return new FieldOr(source(), newChildren.get(0), newChildren.get(1));
    }

    @Override
    protected NodeInfo<? extends Expression> info() {
        return NodeInfo.create(this, FieldOr::new, field, fallback);
    }

    @Override
    public ExpressionEvaluator.Factory toEvaluator(ToEvaluator toEvaluator) {
        throw new UnsupportedOperationException("FieldOr should have been replaced by its surrogate.");
    }

    @Override
    public Expression surrogate() {
        return unset() ? fallback : field;
    }

    private boolean unset() {
        return field instanceof Literal literal && literal.value() == null;
    }
}
