/*
 * Copyright Elasticsearch B.V. and/or licensed to Elasticsearch B.V. under one
 * or more contributor license agreements. Licensed under the Elastic License
 * 2.0; you may not use this file except in compliance with the Elastic License
 * 2.0.
 */

package org.elasticsearch.xpack.esql.expression;

import org.elasticsearch.common.io.stream.StreamOutput;
import org.elasticsearch.xpack.esql.core.expression.Expression;
import org.elasticsearch.xpack.esql.core.expression.LeafExpression;
import org.elasticsearch.xpack.esql.core.expression.Nullability;
import org.elasticsearch.xpack.esql.core.tree.NodeInfo;
import org.elasticsearch.xpack.esql.core.tree.Source;
import org.elasticsearch.xpack.esql.core.type.DataType;

import java.util.List;
import java.util.Objects;

/**
 * A {@code ?param} or {@code ??param} whose value is {@link #VALUE} ("Any" in a Kibana control). The analyzer replaces
 * the nearest boolean expression containing it with {@code true}, and the parser drops it as a {@code BY} key.
 * It's typed {@code NULL} so function resolution and implicit casting leave it alone until then.
 * <p>
 * Prototype: the sentinel value is a placeholder, see KIBANA_ANY_PROPOSALS.md.
 */
public class AnyParameter extends LeafExpression {
    public static final String VALUE = "__ANY__";

    private final String param;

    public AnyParameter(Source source, String param) {
        super(source);
        this.param = param;
    }

    /**
     * Whether a request parameter value means "Any": the sentinel itself, or a one-element list holding it.
     */
    public static boolean isAny(Object value) {
        if (value instanceof List<?> list) {
            return list.size() == 1 && isAny(list.get(0));
        }
        return value != null && VALUE.equals(value.toString());
    }

    public String param() {
        return param;
    }

    @Override
    public Nullability nullable() {
        return Nullability.FALSE;
    }

    @Override
    public DataType dataType() {
        return DataType.NULL;
    }

    @Override
    public String getWriteableName() {
        throw new UnsupportedOperationException("not serialized");
    }

    @Override
    public void writeTo(StreamOutput out) {
        throw new UnsupportedOperationException("not serialized");
    }

    @Override
    protected NodeInfo<? extends Expression> info() {
        return NodeInfo.create(this, AnyParameter::new, param);
    }

    @Override
    public String toString() {
        return param + "=" + VALUE;
    }

    @Override
    public boolean equals(Object obj) {
        return obj != null && getClass() == obj.getClass() && Objects.equals(param, ((AnyParameter) obj).param);
    }

    @Override
    public int hashCode() {
        return Objects.hash(param);
    }
}
