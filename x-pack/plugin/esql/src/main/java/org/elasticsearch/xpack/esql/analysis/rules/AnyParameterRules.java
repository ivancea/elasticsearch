/*
 * Copyright Elasticsearch B.V. and/or licensed to Elasticsearch B.V. under one
 * or more contributor license agreements. Licensed under the Elastic License
 * 2.0; you may not use this file except in compliance with the Elastic License
 * 2.0.
 */

package org.elasticsearch.xpack.esql.analysis.rules;

import org.elasticsearch.xpack.esql.VerificationException;
import org.elasticsearch.xpack.esql.common.Failure;
import org.elasticsearch.xpack.esql.core.capabilities.UnresolvedException;
import org.elasticsearch.xpack.esql.core.expression.Expression;
import org.elasticsearch.xpack.esql.core.expression.Literal;
import org.elasticsearch.xpack.esql.core.expression.NamedExpression;
import org.elasticsearch.xpack.esql.core.type.DataType;
import org.elasticsearch.xpack.esql.expression.AnyParameter;
import org.elasticsearch.xpack.esql.plan.logical.LogicalPlan;
import org.elasticsearch.xpack.esql.rule.Rule;

import java.util.ArrayList;
import java.util.List;

/**
 * "Any" auto-removal: a parameter set to {@link AnyParameter#VALUE} turns the nearest boolean expression containing it
 * into {@code true}, e.g. {@code WHERE MV_INTERSECTS(?os, os)} becomes {@code WHERE true}. Under {@code NOT}, that's
 * {@code NOT true}: "Any" behaves as a value matching everything, not as a removed filter.
 */
public final class AnyParameterRules {
    private AnyParameterRules() {}

    /**
     * Runs in the resolution batch, before implicit casting reads argument types. Bottom-up, so the innermost boolean
     * ancestor is replaced first and outer ones no longer contain the marker. Waits until the children are resolved,
     * because the data type of some functions is only known then.
     */
    public static class ReplaceWithTrue extends Rule<LogicalPlan, LogicalPlan> {
        @Override
        public LogicalPlan apply(LogicalPlan plan) {
            if (plan.anyMatch(p -> p.expressions().stream().anyMatch(e -> e.anyMatch(AnyParameter.class::isInstance))) == false) {
                return plan;
            }
            return plan.transformExpressionsUp(Expression.class, ReplaceWithTrue::replace);
        }

        private static Expression replace(Expression e) {
            if (e instanceof AnyParameter || e instanceof NamedExpression || e.childrenResolved() == false) {
                return e;
            }
            if (e.children().stream().anyMatch(c -> c.anyMatch(AnyParameter.class::isInstance)) && isBoolean(e)) {
                return new Literal(e.source(), Boolean.TRUE, DataType.BOOLEAN);
            }
            return e;
        }

        private static boolean isBoolean(Expression e) {
            try {
                return e.dataType() == DataType.BOOLEAN;
            } catch (UnresolvedException ex) {
                return false;
            }
        }
    }

    /**
     * Fails analysis when a marker has no boolean ancestor, e.g. {@code EVAL x = ?v}. {@code BY} keys and identifier
     * positions are handled by the parser.
     */
    public static class FailOnRemaining extends Rule<LogicalPlan, LogicalPlan> {
        @Override
        public LogicalPlan apply(LogicalPlan plan) {
            List<Failure> failures = new ArrayList<>();
            plan.forEachExpressionUp(
                AnyParameter.class,
                any -> failures.add(
                    Failure.fail(
                        any,
                        "Query parameter [{}] is [{}], which is only allowed inside a boolean condition or as a BY key",
                        any.param(),
                        AnyParameter.VALUE
                    )
                )
            );
            if (failures.isEmpty() == false) {
                throw new VerificationException(failures);
            }
            return plan;
        }
    }
}
