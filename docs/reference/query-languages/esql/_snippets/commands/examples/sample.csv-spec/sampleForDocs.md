% This is generated by ESQL's AbstractFunctionTestCase. Do not edit it. See ../README.md for how to regenerate it.

```esql
FROM employees
| KEEP emp_no
| SAMPLE 0.05
```

| emp_no:integer |
| --- |
| 10018 |
| 10024 |
| 10062 |
| 10081 |
