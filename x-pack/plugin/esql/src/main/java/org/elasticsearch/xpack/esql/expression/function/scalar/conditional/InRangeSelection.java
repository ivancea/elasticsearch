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
import org.elasticsearch.xpack.esql.core.expression.MapExpression;
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
import org.elasticsearch.xpack.esql.expression.function.scalar.multivalue.MvGreater;
import org.elasticsearch.xpack.esql.expression.function.scalar.multivalue.MvInRange;
import org.elasticsearch.xpack.esql.expression.function.scalar.multivalue.MvLess;

import java.io.IOException;
import java.util.List;

/**
 * Prototype sugar for range controls: {@code IN_RANGE_SELECTION(field, ?lower, ?upper)} is true when any value of
 * {@code field} is within the inclusive bounds. A {@code null} bound is unbounded, so both {@code null} is "Any".
 */
public class InRangeSelection extends EsqlScalarFunction implements OnlySurrogateExpression {
    public static final FunctionDefinition DEFINITION = FunctionDefinition.def(InRangeSelection.class)
        .ternary(InRangeSelection::new)
        .name("in_range_selection");

    private final Expression field;
    private final Expression lower;
    private final Expression upper;

    @FunctionInfo(
        returnType = "boolean",
        description = "Returns `true` when any value of `field` is within `[lower, upper]`; a `null` bound is unbounded.",
        preview = true,
        appliesTo = { @FunctionAppliesTo(lifeCycle = FunctionAppliesToLifecycle.PREVIEW, version = "9.6.0") }
    )
    public InRangeSelection(
        Source source,
        @Param(name = "field", type = { "date", "double", "integer", "ip", "keyword", "long" }, description = "Field to filter.")
        Expression field,
        @Param(name = "lower", type = { "date", "double", "integer", "ip", "keyword", "long" }, description = "Lower bound or `null`.")
        Expression lower,
        @Param(name = "upper", type = { "date", "double", "integer", "ip", "keyword", "long" }, description = "Upper bound or `null`.")
        Expression upper
    ) {
        super(source, List.of(field, lower, upper));
        this.field = field;
        this.lower = lower;
        this.upper = upper;
    }

    @Override
    public String getWriteableName() {
        throw new UnsupportedOperationException("InRangeSelection does not support serialization.");
    }

    @Override
    public void writeTo(StreamOutput out) throws IOException {
        throw new UnsupportedOperationException("InRangeSelection does not support serialization.");
    }

    @Override
    protected TypeResolution resolveType() {
        return childrenResolved() ? TypeResolution.TYPE_RESOLVED : new TypeResolution("Unresolved children");
    }

    @Override
    public DataType dataType() {
        return DataType.BOOLEAN;
    }

    @Override
    public boolean foldable() {
        return false;
    }

    @Override
    public Expression replaceChildren(List<Expression> newChildren) {
        return new InRangeSelection(source(), newChildren.get(0), newChildren.get(1), newChildren.get(2));
    }

    @Override
    protected NodeInfo<? extends Expression> info() {
        return NodeInfo.create(this, InRangeSelection::new, field, lower, upper);
    }

    @Override
    public ExpressionEvaluator.Factory toEvaluator(ToEvaluator toEvaluator) {
        throw new UnsupportedOperationException("InRangeSelection should have been replaced by its surrogate.");
    }

    @Override
    public Expression surrogate() {
        boolean noLower = isNull(lower);
        boolean noUpper = isNull(upper);
        if (noLower && noUpper) {
            return Literal.TRUE;
        }
        if (noLower) {
            return new MvLess(source(), field, castToField(upper), inclusive());
        }
        if (noUpper) {
            return new MvGreater(source(), field, castToField(lower), inclusive());
        }
        return new MvInRange(source(), field, castToField(lower), castToField(upper));
    }

    private Expression castToField(Expression bound) {
        return InSelection.castTo(source(), bound, field.dataType());
    }

    private static boolean isNull(Expression bound) {
        return bound instanceof Literal literal && literal.value() == null;
    }

    private MapExpression inclusive() {
        return new MapExpression(source(), List.of(Literal.keyword(source(), "include_bound"), Literal.TRUE));
    }
}
