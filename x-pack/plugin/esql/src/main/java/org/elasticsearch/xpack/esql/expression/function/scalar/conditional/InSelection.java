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
import org.elasticsearch.xpack.esql.expression.function.MapParam;
import org.elasticsearch.xpack.esql.expression.function.OptionalArgument;
import org.elasticsearch.xpack.esql.expression.function.Param;
import org.elasticsearch.xpack.esql.expression.function.scalar.EsqlScalarFunction;
import org.elasticsearch.xpack.esql.expression.function.scalar.convert.ToBoolean;
import org.elasticsearch.xpack.esql.expression.function.scalar.multivalue.MvContains;
import org.elasticsearch.xpack.esql.expression.function.scalar.multivalue.MvIntersects;
import org.elasticsearch.xpack.esql.expression.function.scalar.nulls.Coalesce;
import org.elasticsearch.xpack.esql.expression.predicate.logical.And;
import org.elasticsearch.xpack.esql.expression.predicate.logical.Not;
import org.elasticsearch.xpack.esql.expression.predicate.logical.Or;
import org.elasticsearch.xpack.esql.expression.predicate.nulls.IsNull;
import org.elasticsearch.xpack.esql.type.EsqlDataTypeConverter;

import java.io.IOException;
import java.util.ArrayList;
import java.util.List;

/**
 * Prototype sugar for dashboard controls: {@code IN_SELECTION(field, ?selection [, options])} is true when the
 * selection is "Any" ({@code null}) or when any value of {@code field} is selected. It always lowers to the
 * {@code ?x IS NULL OR MV_INTERSECTS(?x, field)} family of templates, so it folds and pushes down like them.
 */
public class InSelection extends EsqlScalarFunction implements OnlySurrogateExpression, OptionalArgument {
    public static final FunctionDefinition DEFINITION = FunctionDefinition.def(InSelection.class)
        .ternary(InSelection::new)
        .name("in_selection");

    private final Expression field;
    private final Expression selection;
    private final Expression options;

    @FunctionInfo(
        returnType = "boolean",
        description = "Returns `true` when `selection` is `null` (\"Any\") or when any value of `field` is in `selection`.",
        preview = true,
        appliesTo = { @FunctionAppliesTo(lifeCycle = FunctionAppliesToLifecycle.PREVIEW, version = "9.6.0") }
    )
    public InSelection(
        Source source,
        @Param(name = "field", type = { "boolean", "integer", "ip", "keyword", "long", "text" }, description = "Field to filter.")
        Expression field,
        @Param(
            name = "selection",
            type = { "boolean", "integer", "ip", "keyword", "long", "text" },
            description = "Selected value or values; `null` means \"Any\"."
        ) Expression selection,
        @MapParam(
            name = "options",
            params = {
                @MapParam.MapParamEntry(
                    name = "nulls",
                    type = "boolean",
                    description = "Whether \"(No value)\" is selected, as one more option: alone it selects only documents "
                        + "without a value."
                ),
                @MapParam.MapParamEntry(
                    name = "include_nulls",
                    type = "boolean",
                    description = "Also match documents without a value when there is a selection; no effect on \"Any\"."
                ),
                @MapParam.MapParamEntry(
                    name = "null_value",
                    type = "keyword",
                    description = "Sentinel value in `selection` that stands for \"(No value)\"."
                ) },
            description = "(Optional) Blank handling.",
            optional = true
        ) Expression options
    ) {
        super(source, options == null ? List.of(field, selection) : List.of(field, selection, options));
        this.field = field;
        this.selection = selection;
        this.options = options;
    }

    @Override
    public String getWriteableName() {
        throw new UnsupportedOperationException("InSelection does not support serialization.");
    }

    @Override
    public void writeTo(StreamOutput out) throws IOException {
        throw new UnsupportedOperationException("InSelection does not support serialization.");
    }

    @Override
    protected TypeResolution resolveType() {
        if (childrenResolved() == false) {
            return new TypeResolution("Unresolved children");
        }
        if (options != null && options instanceof MapExpression == false) {
            return new TypeResolution("third argument of [" + sourceText() + "] must be a map");
        }
        return TypeResolution.TYPE_RESOLVED;
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
        return new InSelection(source(), newChildren.get(0), newChildren.get(1), newChildren.size() > 2 ? newChildren.get(2) : null);
    }

    @Override
    protected NodeInfo<? extends Expression> info() {
        return NodeInfo.create(this, InSelection::new, field, selection, options);
    }

    @Override
    public ExpressionEvaluator.Factory toEvaluator(ToEvaluator toEvaluator) {
        throw new UnsupportedOperationException("InSelection should have been replaced by its surrogate.");
    }

    @Override
    public Expression surrogate() {
        Source src = source();
        Expression any = new IsNull(src, selection);
        Expression match = new MvIntersects(src, castTo(src, selection, field.dataType()), field);
        Expression nulls = option("nulls");
        if (nulls != null) {
            any = new And(src, any, new Not(src, nulls));
            match = new Or(src, match, new And(src, nulls, new IsNull(src, field)));
        }
        Expression includeNulls = option("include_nulls");
        if (includeNulls != null) {
            match = new Or(src, match, new And(src, includeNulls, new IsNull(src, field)));
        }
        Expression nullValue = options == null ? null : ((MapExpression) options).keyFoldedMap().get("null_value");
        if (nullValue != null) {
            match = new Or(src, match, new And(src, new IsNull(src, field), new MvContains(src, selection, nullValue)));
        }
        return new Or(src, any, match);
    }

    /** Casts a control value to the field type: controls send strings for non-numeric fields and integers for longs. */
    static Expression castTo(Source source, Expression value, DataType to) {
        DataType from = value.dataType();
        if (from == to || from == DataType.NULL || (DataType.isString(from) && DataType.isString(to))) {
            return value;
        }
        var converter = EsqlDataTypeConverter.converterFunctionFactory(to);
        return converter == null ? value : converter.apply(source, value, null);
    }

    /** A boolean option, accepting `"true"`/`"false"` strings and treating `null` as `false`. */
    private Expression option(String name) {
        if (options == null) {
            return null;
        }
        Expression value = ((MapExpression) options).keyFoldedMap().get(name);
        if (value == null) {
            return null;
        }
        if (value.dataType() != DataType.BOOLEAN && value.dataType() != DataType.NULL) {
            value = new ToBoolean(source(), value);
        }
        List<Expression> rest = new ArrayList<>(1);
        rest.add(Literal.FALSE);
        return new Coalesce(source(), value, rest);
    }
}
