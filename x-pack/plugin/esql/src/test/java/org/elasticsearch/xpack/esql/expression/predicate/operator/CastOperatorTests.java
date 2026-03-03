/*
 * Copyright Elasticsearch B.V. and/or licensed to Elasticsearch B.V. under one
 * or more contributor license agreements. Licensed under the Elastic License
 * 2.0; you may not use this file except in compliance with the Elastic License
 * 2.0.
 */

package org.elasticsearch.xpack.esql.expression.predicate.operator;

import org.elasticsearch.test.ESTestCase;
import org.elasticsearch.xpack.esql.expression.function.DocsV3Support;
import org.elasticsearch.xpack.esql.expression.function.scalar.math.Cast;
import org.junit.AfterClass;

import java.util.Set;

public class CastOperatorTests extends ESTestCase {
    public void testDummy() {
        assert true;
    }

    @AfterClass
    public static void renderDocs() throws Exception {
        if (System.getProperty("generateDocs") == null) {
            return;
        }
        DocsV3Support.OperatorConfig op = new DocsV3Support.OperatorConfig(
            "cast",
            "::",
            Cast.OperatorDocs.class,
            DocsV3Support.OperatorCategory.CAST
        );
        var docs = new DocsV3Support.OperatorsDocsSupport(
            "cast",
            CastOperatorTests.class,
            op,
            CastOperatorTests::signatures,
            DocsV3Support.callbacksFromSystemProperty()
        );
        docs.renderSignature();
        docs.renderDocs();
    }

    public static Set<DocsV3Support.TypeSignature> signatures() {
        // The cast operator cannot produce sensible signatures unless we consider the type as an extra parameter
        return Set.of();
    }
}
