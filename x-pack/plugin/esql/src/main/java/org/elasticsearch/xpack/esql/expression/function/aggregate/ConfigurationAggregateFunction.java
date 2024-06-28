/*
 * Copyright Elasticsearch B.V. and/or licensed to Elasticsearch B.V. under one
 * or more contributor license agreements. Licensed under the Elastic License
 * 2.0; you may not use this file except in compliance with the Elastic License
 * 2.0.
 */
package org.elasticsearch.xpack.esql.expression.function.aggregate;

import org.elasticsearch.common.io.stream.StreamInput;
import org.elasticsearch.common.io.stream.StreamOutput;
import org.elasticsearch.xpack.esql.core.expression.Expression;
import org.elasticsearch.xpack.esql.core.session.Configuration;
import org.elasticsearch.xpack.esql.core.tree.Source;
import org.elasticsearch.xpack.esql.io.stream.PlanStreamInput;
import org.elasticsearch.xpack.esql.io.stream.PlanStreamOutput;

import java.io.IOException;
import java.util.List;
import java.util.Objects;

/**
 * A type of {@code AggregateFunction} that has a {@code Configuration} object.
 */
public abstract class ConfigurationAggregateFunction extends AggregateFunction {

    private final Configuration configuration;

    protected ConfigurationAggregateFunction(Source source, Expression field, Configuration configuration) {
        super(source, field);
        this.configuration = configuration;
    }

    protected ConfigurationAggregateFunction(
        Source source,
        Expression field,
        List<? extends Expression> parameters,
        Configuration configuration
    ) {
        super(source, field, parameters);
        this.configuration = configuration;
    }

    protected ConfigurationAggregateFunction(StreamInput in) throws IOException {
        this(Source.readFrom((PlanStreamInput) in), ((PlanStreamInput) in).readExpression(), ((PlanStreamInput) in).configuration());
    }

    public Configuration configuration() {
        return configuration;
    }

    @Override
    public void writeTo(StreamOutput out) throws IOException {
        Source.EMPTY.writeTo(out);
        ((PlanStreamOutput) out).writeExpression(field());
    }

    @Override
    public int hashCode() {
        return Objects.hash(getClass(), children(), configuration());
    }

    @Override
    public boolean equals(Object obj) {
        if (super.equals(obj)) {
            ConfigurationAggregateFunction other = (ConfigurationAggregateFunction) obj;
            return Objects.equals(other.field(), field())
                && Objects.equals(other.parameters(), parameters())
                && Objects.equals(other.configuration(), configuration());
        }
        return false;
    }
}
