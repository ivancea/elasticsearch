/*
 * Copyright Elasticsearch B.V. and/or licensed to Elasticsearch B.V. under one
 * or more contributor license agreements. Licensed under the Elastic License
 * 2.0; you may not use this file except in compliance with the Elastic License
 * 2.0.
 */

package org.elasticsearch.xpack.esql.optimizer.rules.logical;

import org.elasticsearch.xpack.esql.core.expression.Alias;
import org.elasticsearch.xpack.esql.core.expression.Attribute;
import org.elasticsearch.xpack.esql.core.expression.Expression;
import org.elasticsearch.xpack.esql.plan.logical.Eval;
import org.elasticsearch.xpack.esql.plan.logical.Limit;
import org.elasticsearch.xpack.esql.plan.logical.LogicalPlan;
import org.elasticsearch.xpack.esql.plan.logical.OrderBy;
import org.elasticsearch.xpack.esql.plan.logical.Project;

import java.util.ArrayList;
import java.util.List;

import static org.elasticsearch.xpack.esql.core.expression.Attribute.rawTemporaryName;

/**
 * Replace nested expressions inside a {@link Limit}'s groupings (LIMIT BY) with synthetic eval.
 * {@code SORT salary | LIMIT 2 BY languages * 2}
 * becomes
 * {@code SORT salary | EVAL $$limit_by_0 = languages * 2 | LIMIT 2 BY $$limit_by_0}
 * The eval is inserted below the {@link OrderBy} to preserve the {@code Limit -> OrderBy} structure
 * needed by {@link ReplaceLimitAndSortAsTopN}.
 */
public final class ReplaceLimitByExpressionWithEval extends OptimizerRules.OptimizerRule<Limit> {

    @Override
    protected LogicalPlan rule(Limit limit) {
        if (limit.groupings().isEmpty()) {
            return limit;
        }

        List<Expression> groupings = limit.groupings();
        int size = groupings.size();
        int counter = 0;
        List<Alias> evals = new ArrayList<>(size);
        List<Expression> newGroupings = new ArrayList<>(groupings);

        for (int i = 0; i < size; i++) {
            Expression g = newGroupings.get(i);
            if (g instanceof Attribute == false) {
                var name = rawTemporaryName("LIMIT BY", String.valueOf(i), String.valueOf(counter++));
                var alias = new Alias(g.source(), name, g, null, true);
                evals.add(alias);
                newGroupings.set(i, alias.toAttribute());
            }
        }

        if (evals.isEmpty()) {
            return limit;
        }

        // Insert Eval below OrderBy to preserve Limit -> OrderBy structure for ReplaceLimitAndSortAsTopN
        var originalOutput = limit.output();
        var child = limit.child();
        LogicalPlan evalChild;
        if (child instanceof OrderBy orderBy) {
            evalChild = new OrderBy(orderBy.source(), new Eval(orderBy.source(), orderBy.child(), evals), orderBy.order());
        } else {
            evalChild = new Eval(limit.source(), child, evals);
        }

        var newLimit = new Limit(limit.source(), limit.limit(), evalChild, newGroupings, limit.duplicated(), limit.local());
        return new Project(limit.source(), newLimit, originalOutput);
    }
}
