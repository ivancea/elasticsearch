/*
 * Copyright Elasticsearch B.V. and/or licensed to Elasticsearch B.V. under one
 * or more contributor license agreements. Licensed under the Elastic License
 * 2.0; you may not use this file except in compliance with the Elastic License
 * 2.0.
 */

package org.elasticsearch.xpack.esql.optimizer.rules.logical;

import org.elasticsearch.TransportVersion;
import org.elasticsearch.test.ESTestCase;
import org.elasticsearch.xpack.esql.core.expression.Expression;
import org.elasticsearch.xpack.esql.core.type.DataType;
import org.elasticsearch.xpack.esql.expression.function.aggregate.Sum;

import static org.elasticsearch.xpack.esql.EsqlTestUtils.getFieldAttribute;
import static org.elasticsearch.xpack.esql.action.EsqlExecutionInfo.EXECUTION_PROFILE_FORMAT_VERSION;
import static org.elasticsearch.xpack.esql.core.tree.Source.EMPTY;
import static org.hamcrest.Matchers.instanceOf;
import static org.hamcrest.Matchers.is;
import static org.hamcrest.Matchers.not;
import static org.hamcrest.Matchers.sameInstance;

public class SubstituteTransportVersionAwareExpressionsTests extends ESTestCase {
    public void testSumReplacedWithOldVersion() {
        Expression field = getFieldAttribute("f", DataType.LONG);
        Sum sum = new Sum(EMPTY, field);
        Expression result = SubstituteTransportVersionAwareExpressions.rule(sum, EXECUTION_PROFILE_FORMAT_VERSION);
        assertThat(result, instanceOf(Sum.class));
        assertThat(((Sum) result).useOverflowingLongSupplier(), is(true));
        assertThat(result, is(not(sameInstance(sum))));
    }

    public void testSumNotReplacedWithCurrentVersion() {
        Expression field = getFieldAttribute("f", DataType.LONG);
        Sum sum = new Sum(EMPTY, field);
        Expression result = SubstituteTransportVersionAwareExpressions.rule(sum, TransportVersion.current());
        assertThat(result, sameInstance(sum));
        assertThat(sum.useOverflowingLongSupplier(), is(false));
    }

    public void testNonTransportVersionAwareUnchanged() {
        Expression field = getFieldAttribute("f", DataType.LONG);
        Expression result = SubstituteTransportVersionAwareExpressions.rule(field, EXECUTION_PROFILE_FORMAT_VERSION);
        assertThat(result, sameInstance(field));
    }
}
