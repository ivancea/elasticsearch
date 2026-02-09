/*
 * Copyright Elasticsearch B.V. and/or licensed to Elasticsearch B.V. under one
 * or more contributor license agreements. Licensed under the Elastic License
 * 2.0; you may not use this file except in compliance with the Elastic License
 * 2.0.
 */

package org.elasticsearch.compute.data;

import org.apache.lucene.util.BytesRef;
import org.elasticsearch.common.breaker.CircuitBreaker;
import org.elasticsearch.common.unit.ByteSizeValue;
import org.elasticsearch.common.util.BigArrays;
import org.elasticsearch.common.util.MockBigArrays;
import org.elasticsearch.common.util.PageCacheRecycler;
import org.elasticsearch.indices.breaker.CircuitBreakerService;
import org.elasticsearch.test.ESTestCase;
import org.junit.After;
import org.junit.Before;

import java.util.List;

import static org.elasticsearch.compute.test.BlockTestUtils.valuesAtPositions;
import static org.hamcrest.Matchers.equalTo;
import static org.hamcrest.Matchers.instanceOf;
import static org.hamcrest.Matchers.is;
import static org.hamcrest.Matchers.nullValue;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.when;

/**
 * Tests for ConstantMultivalueBlock implementations.
 */
public class ConstantMultivalueBlockTests extends ESTestCase {

    final CircuitBreaker breaker = new MockBigArrays.LimitedBreaker("esql-test-breaker", ByteSizeValue.ofGb(1));
    final BigArrays bigArrays = new MockBigArrays(PageCacheRecycler.NON_RECYCLING_INSTANCE, mockBreakerService(breaker));
    final BlockFactory blockFactory = BlockFactory.getInstance(breaker, bigArrays);

    @Before
    @After
    public void checkBreaker() {
        assertThat(breaker.getUsed(), is(0L));
    }

    // --- Int tests ---

    public void testIntConstantMultivalueBlockBasics() {
        int positionCount = randomIntBetween(1, 100);
        int[] values = new int[] { 1, 2, 3 };

        // The block takes ownership of the vector, so don't close the vector separately
        IntVector vector = blockFactory.newIntArrayVector(values, values.length);
        try (IntBlock block = blockFactory.newConstantIntMultivalueBlockWith(vector, positionCount)) {
            assertThat(block, instanceOf(ConstantIntMultivalueBlock.class));
            assertThat(block.getPositionCount(), equalTo(positionCount));
            assertThat(block.getTotalValueCount(), equalTo(positionCount * values.length));
            assertThat(block.asVector(), nullValue());
            assertThat(block.mayHaveMultivaluedFields(), equalTo(true));
            assertThat(block.doesHaveMultivaluedFields(), equalTo(true));
            assertThat(block.mayHaveNulls(), equalTo(false));
            assertThat(block.areAllValuesNull(), equalTo(false));

            for (int p = 0; p < positionCount; p++) {
                assertThat(block.isNull(p), equalTo(false));
                assertThat(block.getValueCount(p), equalTo(values.length));
                assertThat(block.getFirstValueIndex(p), equalTo(0));
                for (int v = 0; v < values.length; v++) {
                    assertThat(block.getInt(v), equalTo(values[v]));
                }
            }
        }
    }

    public void testIntConstantMultivalueBlockExpand() {
        int positionCount = randomIntBetween(1, 50);
        int[] values = new int[] { 10, 20, 30 };

        // The block takes ownership of the vector, so don't close the vector separately
        IntVector vector = blockFactory.newIntArrayVector(values, values.length);
        try (IntBlock block = blockFactory.newConstantIntMultivalueBlockWith(vector, positionCount)) {
            try (IntBlock expanded = block.expand()) {
                // After expansion, we should have positionCount * values.length positions
                int expectedExpandedPositions = positionCount * values.length;
                assertThat(expanded.getPositionCount(), equalTo(expectedExpandedPositions));
                assertThat(expanded.getTotalValueCount(), equalTo(expectedExpandedPositions));

                // Each expanded position should have exactly one value
                for (int p = 0; p < expectedExpandedPositions; p++) {
                    assertThat(expanded.getValueCount(p), equalTo(1));
                    assertThat(expanded.isNull(p), equalTo(false));
                    // Values should repeat: [10, 20, 30, 10, 20, 30, ...]
                    int expectedValue = values[p % values.length];
                    assertThat(expanded.getInt(expanded.getFirstValueIndex(p)), equalTo(expectedValue));
                }
            }
        }
    }

    public void testIntConstantMultivalueBlockSingleValue() {
        // When there's only one value, doesHaveMultivaluedFields should return false
        int positionCount = randomIntBetween(1, 100);
        int[] values = new int[] { 42 };

        // The block takes ownership of the vector, so don't close the vector separately
        IntVector vector = blockFactory.newIntArrayVector(values, values.length);
        try (IntBlock block = blockFactory.newConstantIntMultivalueBlockWith(vector, positionCount)) {
            assertThat(block.mayHaveMultivaluedFields(), equalTo(true));
            assertThat(block.doesHaveMultivaluedFields(), equalTo(false));
        }
    }

    // --- Long tests ---

    public void testLongConstantMultivalueBlockExpand() {
        int positionCount = randomIntBetween(1, 50);
        long[] values = new long[] { 100L, 200L, 300L, 400L };

        // The block takes ownership of the vector, so don't close the vector separately
        LongVector vector = blockFactory.newLongArrayVector(values, values.length);
        try (LongBlock block = blockFactory.newConstantLongMultivalueBlockWith(vector, positionCount)) {
            try (LongBlock expanded = block.expand()) {
                int expectedExpandedPositions = positionCount * values.length;
                assertThat(expanded.getPositionCount(), equalTo(expectedExpandedPositions));

                for (int p = 0; p < expectedExpandedPositions; p++) {
                    assertThat(expanded.getValueCount(p), equalTo(1));
                    long expectedValue = values[p % values.length];
                    assertThat(expanded.getLong(expanded.getFirstValueIndex(p)), equalTo(expectedValue));
                }
            }
        }
    }

    // --- Double tests ---

    public void testDoubleConstantMultivalueBlockExpand() {
        int positionCount = randomIntBetween(1, 50);
        double[] values = new double[] { 1.1, 2.2, 3.3 };

        // The block takes ownership of the vector, so don't close the vector separately
        DoubleVector vector = blockFactory.newDoubleArrayVector(values, values.length);
        try (DoubleBlock block = blockFactory.newConstantDoubleMultivalueBlockWith(vector, positionCount)) {
            try (DoubleBlock expanded = block.expand()) {
                int expectedExpandedPositions = positionCount * values.length;
                assertThat(expanded.getPositionCount(), equalTo(expectedExpandedPositions));

                for (int p = 0; p < expectedExpandedPositions; p++) {
                    assertThat(expanded.getValueCount(p), equalTo(1));
                    double expectedValue = values[p % values.length];
                    assertThat(expanded.getDouble(expanded.getFirstValueIndex(p)), equalTo(expectedValue));
                }
            }
        }
    }

    // --- Boolean tests ---

    public void testBooleanConstantMultivalueBlockExpand() {
        int positionCount = randomIntBetween(1, 50);
        boolean[] values = new boolean[] { true, false, true };

        // The block takes ownership of the vector, so don't close the vector separately
        BooleanVector vector = blockFactory.newBooleanArrayVector(values, values.length);
        try (BooleanBlock block = blockFactory.newConstantBooleanMultivalueBlockWith(vector, positionCount)) {
            try (BooleanBlock expanded = block.expand()) {
                int expectedExpandedPositions = positionCount * values.length;
                assertThat(expanded.getPositionCount(), equalTo(expectedExpandedPositions));

                for (int p = 0; p < expectedExpandedPositions; p++) {
                    assertThat(expanded.getValueCount(p), equalTo(1));
                    boolean expectedValue = values[p % values.length];
                    assertThat(expanded.getBoolean(expanded.getFirstValueIndex(p)), equalTo(expectedValue));
                }
            }
        }
    }

    public void testBooleanConstantMultivalueBlockToMask() {
        int positionCount = randomIntBetween(1, 50);
        // When all values are true, toMask should return true for all positions
        boolean[] allTrue = new boolean[] { true, true };

        // The block takes ownership of the vector, so don't close the vector separately
        BooleanVector vector1 = blockFactory.newBooleanArrayVector(allTrue, allTrue.length);
        try (BooleanBlock block = blockFactory.newConstantBooleanMultivalueBlockWith(vector1, positionCount)) {
            try (ToMask mask = block.toMask()) {
                assertThat(mask.hadMultivaluedFields(), equalTo(true));
                for (int p = 0; p < positionCount; p++) {
                    assertThat(mask.mask().getBoolean(p), equalTo(true));
                }
            }
        }

        // When not all values are true, toMask should return false for all positions
        boolean[] mixed = new boolean[] { true, false };

        // The block takes ownership of the vector, so don't close the vector separately
        BooleanVector vector2 = blockFactory.newBooleanArrayVector(mixed, mixed.length);
        try (BooleanBlock block = blockFactory.newConstantBooleanMultivalueBlockWith(vector2, positionCount)) {
            try (ToMask mask = block.toMask()) {
                assertThat(mask.hadMultivaluedFields(), equalTo(true));
                for (int p = 0; p < positionCount; p++) {
                    assertThat(mask.mask().getBoolean(p), equalTo(false));
                }
            }
        }
    }

    // --- BytesRef tests ---

    public void testBytesRefConstantMultivalueBlockExpand() {
        int positionCount = randomIntBetween(1, 50);
        BytesRef[] values = new BytesRef[] { new BytesRef("a"), new BytesRef("b"), new BytesRef("c") };

        try (BytesRefVector.Builder builder = blockFactory.newBytesRefVectorBuilder(values.length)) {
            for (BytesRef value : values) {
                builder.appendBytesRef(value);
            }
            // The block takes ownership of the vector, so don't close the vector separately
            BytesRefVector vector = builder.build();
            try (BytesRefBlock block = blockFactory.newConstantBytesRefMultivalueBlockWith(vector, positionCount)) {
                try (BytesRefBlock expanded = block.expand()) {
                    int expectedExpandedPositions = positionCount * values.length;
                    assertThat(expanded.getPositionCount(), equalTo(expectedExpandedPositions));

                    BytesRef scratch = new BytesRef();
                    for (int p = 0; p < expectedExpandedPositions; p++) {
                        assertThat(expanded.getValueCount(p), equalTo(1));
                        BytesRef expectedValue = values[p % values.length];
                        assertThat(expanded.getBytesRef(expanded.getFirstValueIndex(p), scratch), equalTo(expectedValue));
                    }
                }
            }
        }
    }

    // --- Filter tests ---

    public void testIntConstantMultivalueBlockFilter() {
        int positionCount = 10;
        int[] values = new int[] { 1, 2, 3 };
        int[] filterPositions = new int[] { 0, 2, 5, 9 };

        // The block takes ownership of the vector, so don't close the vector separately
        IntVector vector = blockFactory.newIntArrayVector(values, values.length);
        try (IntBlock block = blockFactory.newConstantIntMultivalueBlockWith(vector, positionCount)) {
            try (IntBlock filtered = block.filter(filterPositions)) {
                assertThat(filtered.getPositionCount(), equalTo(filterPositions.length));

                for (int p = 0; p < filterPositions.length; p++) {
                    assertThat(filtered.getValueCount(p), equalTo(values.length));
                    List<Object> positionValues = valuesAtPositions(filtered, p, p + 1).get(0);
                    assertThat(positionValues, equalTo(List.of(1, 2, 3)));
                }
            }
        }
    }

    // --- DeepCopy tests ---

    public void testIntConstantMultivalueBlockDeepCopy() {
        int positionCount = randomIntBetween(1, 100);
        int[] values = new int[] { 5, 10, 15 };

        // The block takes ownership of the vector, so don't close the vector separately
        IntVector vector = blockFactory.newIntArrayVector(values, values.length);
        try (IntBlock block = blockFactory.newConstantIntMultivalueBlockWith(vector, positionCount)) {
            try (IntBlock copy = block.deepCopy(blockFactory)) {
                assertThat(copy, instanceOf(ConstantIntMultivalueBlock.class));
                assertThat(copy.getPositionCount(), equalTo(positionCount));

                for (int p = 0; p < positionCount; p++) {
                    assertThat(copy.getValueCount(p), equalTo(values.length));
                    for (int v = 0; v < values.length; v++) {
                        assertThat(copy.getInt(v), equalTo(values[v]));
                    }
                }
            }
        }
    }

    // --- KeepMask tests ---

    public void testIntConstantMultivalueBlockKeepMask() {
        int positionCount = 5;
        int[] values = new int[] { 1, 2, 3 };
        boolean[] mask = new boolean[] { true, false, true, false, true };

        // The block takes ownership of the vector, so don't close the vector separately
        IntVector vector = blockFactory.newIntArrayVector(values, values.length);
        try (
            IntBlock block = blockFactory.newConstantIntMultivalueBlockWith(vector, positionCount);
            BooleanVector maskVector = blockFactory.newBooleanArrayVector(mask, mask.length);
            IntBlock masked = block.keepMask(maskVector)
        ) {
            assertThat(masked.getPositionCount(), equalTo(positionCount));

            for (int p = 0; p < positionCount; p++) {
                if (mask[p]) {
                    assertThat(masked.isNull(p), equalTo(false));
                    assertThat(masked.getValueCount(p), equalTo(values.length));
                } else {
                    assertThat(masked.isNull(p), equalTo(true));
                }
            }
        }
    }

    static CircuitBreakerService mockBreakerService(CircuitBreaker breaker) {
        CircuitBreakerService breakerService = mock(CircuitBreakerService.class);
        when(breakerService.getBreaker(CircuitBreaker.REQUEST)).thenReturn(breaker);
        return breakerService;
    }
}
