/*
 * Copyright Elasticsearch B.V. and/or licensed to Elasticsearch B.V. under one
 * or more contributor license agreements. Licensed under the Elastic License
 * 2.0; you may not use this file except in compliance with the Elastic License
 * 2.0.
 */

package org.elasticsearch.xpack.esql.expression.function.scalar.string;

import com.carrotsearch.randomizedtesting.annotations.Name;
import com.carrotsearch.randomizedtesting.annotations.ParametersFactory;

import org.apache.lucene.util.BytesRef;
import org.elasticsearch.core.Nullable;
import org.elasticsearch.xpack.esql.core.expression.Expression;
import org.elasticsearch.xpack.esql.core.tree.Source;
import org.elasticsearch.xpack.esql.core.type.DataType;
import org.elasticsearch.xpack.esql.expression.function.AbstractScalarFunctionTestCase;
import org.elasticsearch.xpack.esql.expression.function.TestCaseSupplier;

import java.util.ArrayList;
import java.util.List;
import java.util.Locale;
import java.util.function.Function;
import java.util.function.Supplier;

import static org.hamcrest.Matchers.equalTo;

/**
 * Tests for {@link Locate} function.
 */
public class ContainsTests extends AbstractScalarFunctionTestCase {
    public ContainsTests(@Name("TestCase") Supplier<TestCaseSupplier.TestCase> testCaseSupplier) {
        this.testCase = testCaseSupplier.get();
    }

    @ParametersFactory
    public static Iterable<Object[]> parameters() {
        List<TestCaseSupplier> suppliers = new ArrayList<>();
        for (DataType strType : DataType.stringTypes()) {
            for (DataType substrType : DataType.stringTypes()) {
                suppliers.add(
                    supplier(
                        "",
                        strType,
                        substrType,
                        () -> randomRealisticUnicodeOfCodepointLength(10),
                        str -> randomRealisticUnicodeOfCodepointLength(2),
                        String::contains
                    )
                );
                suppliers.add(
                    supplier(
                        "exact match ",
                        strType,
                        substrType,
                        () -> randomRealisticUnicodeOfCodepointLength(10),
                        str -> str,
                        (str, substr) -> true
                    )
                );
            }
        }

        // Here follows some non-randomized examples that we want to cover on every run
        suppliers.add(supplier("a tiger", "a t", true));
        suppliers.add(supplier("a tiger", "a", true));
        suppliers.add(supplier("界世", "界", true));
        suppliers.add(supplier("a tiger", "er", true));
        suppliers.add(supplier("a tiger", "r", true));
        suppliers.add(supplier("界世", "世", true));
        suppliers.add(supplier("a tiger", "ti", true));
        suppliers.add(supplier("a tiger", "ige", true));
        suppliers.add(supplier("世界世", "界", true));
        suppliers.add(supplier("a tiger", "tigers", false));
        suppliers.add(supplier("a tiger", "ipa", false));
        suppliers.add(supplier("世界世", "\uD83C\uDF0D", false));

        suppliers.add(supplier("a ti𠜎er", "𠜎er", true));
        suppliers.add(supplier("a ti𠜎er", "i𠜎e", true));
        suppliers.add(supplier("a ti𠜎er", "ti𠜎", true));
        suppliers.add(supplier("a ti𠜎er", "er", true));
        suppliers.add(supplier("a ti𠜎er", "r", true));
        suppliers.add(supplier("a ti𠜎er", "a ti𠜎er", true));
        // prefix
        suppliers.add(supplier("𠜎abc", "𠜎", true));
        suppliers.add(supplier("𠜎 abc", "𠜎 ", true));
        suppliers.add(supplier("𠜎𠜎𠜎abc", "𠜎𠜎𠜎", true));
        suppliers.add(supplier("𠜎𠜎𠜎 abc", "𠜎𠜎𠜎 ", true));
        suppliers.add(supplier(" 𠜎𠜎𠜎 abc", " 𠜎𠜎𠜎 ", true));
        suppliers.add(supplier("𠜎 𠜎 𠜎 abc", "𠜎 𠜎 𠜎 ", true));
        // suffix
        suppliers.add(supplier("abc𠜎", "𠜎", true));
        suppliers.add(supplier("abc 𠜎", " 𠜎", true));
        suppliers.add(supplier("abc𠜎𠜎𠜎", "𠜎𠜎𠜎", true));
        suppliers.add(supplier("abc 𠜎𠜎𠜎", " 𠜎𠜎𠜎", true));
        suppliers.add(supplier("abc𠜎𠜎𠜎 ", "𠜎𠜎𠜎 ", true));
        // out of range
        suppliers.add(supplier("𠜎a ti𠜎er", "𠜎a ti𠜎ers", false));
        suppliers.add(supplier("a ti𠜎er", "aa ti𠜎er", false));
        suppliers.add(supplier("abc𠜎𠜎", "𠜎𠜎𠜎", false));

        suppliers.add(supplier("🐱Meow!🐶Woof!", "🐱Meow!🐶Woof!", true));
        suppliers.add(supplier("🐱Meow!🐶Woof!", "Meow!🐶Woof!", true));
        suppliers.add(supplier("🐱Meow!🐶Woof!", "eow!🐶Woof!", true));

        // Truncated UTF-8 lead byte 0xF0; must not throw via utf8ToString()
        // Truncated haystack, valid needle
        suppliers.add(supplier(new byte[] { (byte) 'a', (byte) 0xF0 }, "a", true));
        suppliers.add(supplier(new byte[] { (byte) 'a', (byte) 0xF0 }, "z", false));
        // Valid haystack, truncated needle (🐱 is F0 9F 90 B1; lone 0xF0 matches that lead byte)
        suppliers.add(supplier("abc", new byte[] { (byte) 0xF0 }, false));
        suppliers.add(supplier("🐱", new byte[] { (byte) 0xF0 }, true));
        // Both sides truncated; byte-level contains still matches
        suppliers.add(supplier(new byte[] { (byte) 'a', (byte) 0xF0 }, new byte[] { (byte) 0xF0 }, true));
        suppliers.add(supplier(new byte[] { (byte) 'x', (byte) 'a', (byte) 0xF0 }, new byte[] { (byte) 'a', (byte) 0xF0 }, true));
        suppliers.add(supplier(new byte[] { (byte) 'a', (byte) 0xF0 }, new byte[] { (byte) 0xF0, (byte) 0x9F }, false));
        // Both truncated and equal
        suppliers.add(supplier(new byte[] { (byte) 'a', (byte) 0xF0 }, new byte[] { (byte) 'a', (byte) 0xF0 }, true));

        return parameterSuppliersFromTypedDataWithDefaultChecks(true, suppliers);
    }

    @Override
    protected Expression build(Source source, List<Expression> args) {
        return new Contains(source, args.get(0), args.get(1));
    }

    private static TestCaseSupplier supplier(String str, String substr, @Nullable Boolean expectedValue) {
        String name = String.format(Locale.ROOT, "\"%s\" in \"%s\"", substr, str);
        return new TestCaseSupplier(
            name,
            types(DataType.KEYWORD, DataType.KEYWORD),
            () -> testCase(DataType.KEYWORD, DataType.KEYWORD, str, substr, expectedValue)
        );
    }

    private static TestCaseSupplier supplier(byte[] str, String substr, @Nullable Boolean expectedValue) {
        String name = String.format(Locale.ROOT, "\"%s\" in truncated utf8", substr);
        return new TestCaseSupplier(
            name,
            types(DataType.KEYWORD, DataType.KEYWORD),
            () -> testCase(DataType.KEYWORD, DataType.KEYWORD, new BytesRef(str), substr, expectedValue)
        );
    }

    private static TestCaseSupplier supplier(String str, byte[] substr, @Nullable Boolean expectedValue) {
        return new TestCaseSupplier(
            "truncated utf8 in \"" + str + "\"",
            types(DataType.KEYWORD, DataType.KEYWORD),
            () -> testCase(DataType.KEYWORD, DataType.KEYWORD, new BytesRef(str), new BytesRef(substr), expectedValue)
        );
    }

    private static TestCaseSupplier supplier(byte[] str, byte[] substr, @Nullable Boolean expectedValue) {
        return new TestCaseSupplier(
            "truncated utf8 in truncated utf8",
            types(DataType.KEYWORD, DataType.KEYWORD),
            () -> testCase(DataType.KEYWORD, DataType.KEYWORD, new BytesRef(str), new BytesRef(substr), expectedValue)
        );
    }

    interface ExpectedValue {
        boolean expectedValue(String str, String substr);
    }

    private static TestCaseSupplier supplier(
        String name,
        DataType strType,
        DataType substrType,
        Supplier<String> strValueSupplier,
        Function<String, String> substrValueSupplier,
        ExpectedValue expectedValue
    ) {
        List<DataType> types = types(strType, substrType);
        return new TestCaseSupplier(name + TestCaseSupplier.nameFromTypes(types), types, () -> {
            String str = strValueSupplier.get();
            String substr = substrValueSupplier.apply(str);
            return testCase(strType, substrType, str, substr, expectedValue.expectedValue(str, substr));
        });
    }

    private static String expectedToString() {
        return "ContainsEvaluator[str=Attribute[channel=0], substr=Attribute[channel=1]]";
    }

    private static List<DataType> types(DataType firstType, DataType secondType) {
        List<DataType> types = new ArrayList<>();
        types.add(firstType);
        types.add(secondType);
        return types;
    }

    private static TestCaseSupplier.TestCase testCase(
        DataType strType,
        DataType substrType,
        String str,
        String substr,
        Boolean expectedValue
    ) {
        return testCase(strType, substrType, str == null ? null : new BytesRef(str), substr, expectedValue);
    }

    private static TestCaseSupplier.TestCase testCase(
        DataType strType,
        DataType substrType,
        BytesRef str,
        String substr,
        Boolean expectedValue
    ) {
        return testCase(strType, substrType, str, substr == null ? null : new BytesRef(substr), expectedValue);
    }

    private static TestCaseSupplier.TestCase testCase(
        DataType strType,
        DataType substrType,
        BytesRef str,
        BytesRef substr,
        Boolean expectedValue
    ) {
        List<TestCaseSupplier.TypedData> values = new ArrayList<>();
        values.add(new TestCaseSupplier.TypedData(str, strType, "str"));
        values.add(new TestCaseSupplier.TypedData(substr, substrType, "substr"));
        return new TestCaseSupplier.TestCase(values, expectedToString(), DataType.BOOLEAN, equalTo(expectedValue));
    }
}
