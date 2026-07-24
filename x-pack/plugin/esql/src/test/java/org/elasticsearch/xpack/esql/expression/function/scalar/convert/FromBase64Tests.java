/*
 * Copyright Elasticsearch B.V. and/or licensed to Elasticsearch B.V. under one
 * or more contributor license agreements. Licensed under the Elastic License
 * 2.0; you may not use this file except in compliance with the Elastic License
 * 2.0.
 */

package org.elasticsearch.xpack.esql.expression.function.scalar.convert;

import com.carrotsearch.randomizedtesting.annotations.Name;
import com.carrotsearch.randomizedtesting.annotations.ParametersFactory;

import org.apache.lucene.util.BytesRef;
import org.elasticsearch.xpack.esql.core.expression.Expression;
import org.elasticsearch.xpack.esql.core.tree.Source;
import org.elasticsearch.xpack.esql.core.type.DataType;
import org.elasticsearch.xpack.esql.expression.function.AbstractScalarFunctionTestCase;
import org.elasticsearch.xpack.esql.expression.function.FunctionName;
import org.elasticsearch.xpack.esql.expression.function.TestCaseSupplier;
import org.elasticsearch.xpack.esql.expression.function.UnaryTestCaseHelper;

import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.Base64;
import java.util.List;
import java.util.function.Supplier;

import static org.elasticsearch.xpack.esql.expression.function.TestCaseSupplier.unary;

@FunctionName("from_base64")
public class FromBase64Tests extends AbstractScalarFunctionTestCase {
    public FromBase64Tests(@Name("TestCase") Supplier<TestCaseSupplier.TestCase> testCaseSupplier) {
        this.testCase = testCaseSupplier.get();
    }

    @ParametersFactory
    public static Iterable<Object[]> parameters() {
        List<TestCaseSupplier> suppliers = new ArrayList<>();
        UnaryTestCaseHelper valid = unary().expectedOutputType(DataType.KEYWORD)
            .evaluatorToString("FromBase64Evaluator[field=%0]")
            .expectedFromString(s -> new BytesRef(Base64.getDecoder().decode(s.getBytes(StandardCharsets.UTF_8))));
        valid.strings("empty", () -> "").build(suppliers);
        valid.strings("ascii", () -> Base64.getEncoder().encodeToString(randomAlphaOfLengthBetween(1, 54).getBytes(StandardCharsets.UTF_8)))
            .build(suppliers);
        valid.strings(
            "unicode",
            () -> Base64.getEncoder().encodeToString(randomRealisticUnicodeOfCodepointLengthBetween(1, 20).getBytes(StandardCharsets.UTF_8))
        ).build(suppliers);

        UnaryTestCaseHelper invalidUtf8 = unary().expectedOutputType(DataType.KEYWORD)
            .evaluatorToString("FromBase64Evaluator[field=%0]")
            .expectNullAndWarningsFromString(
                s -> List.of("Line 1:1: java.lang.IllegalArgumentException: decoded value is not valid UTF-8")
            );
        // 'a' + truncated 4-byte lead 0xF0
        invalidUtf8.strings("truncated lead", () -> "YfA=").build(suppliers);
        // lone 0xF0
        invalidUtf8.strings("lone lead", () -> "8A==").build(suppliers);

        UnaryTestCaseHelper invalidBase64 = unary().expectedOutputType(DataType.KEYWORD)
            .evaluatorToString("FromBase64Evaluator[field=%0]")
            .expectNullAndWarningsFromString(s -> List.of("Line 1:1: java.lang.IllegalArgumentException: " + base64ErrorMessage(s)));
        invalidBase64.strings("not base64", () -> "not!!base64").build(suppliers);

        return parameterSuppliersFromTypedDataWithDefaultChecks(true, suppliers);
    }

    private static String base64ErrorMessage(String bad) {
        try {
            Base64.getDecoder().decode(bad.getBytes(StandardCharsets.UTF_8));
            throw new AssertionError("expected invalid base64: " + bad);
        } catch (IllegalArgumentException e) {
            return e.getMessage();
        }
    }

    @Override
    protected Expression build(Source source, List<Expression> args) {
        return new FromBase64(source, args.get(0));
    }
}
