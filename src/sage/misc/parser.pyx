"""
This module provides a parser for symbolic equations and expressions.

It is both safer and more powerful than using Python's eval, as one has
complete control over what names are used (including dynamically creating
variables) and how integer and floating point literals are created.

AUTHOR:

- Robert Bradshaw 2008-04 (initial version)
"""

#*****************************************************************************
#     Copyright (C) 2008 Robert Bradshaw <robertwb@math.washington.edu>
#
#  Distributed under the terms of the GNU General Public License (GPL)
#
#    This code is distributed in the hope that it will be useful,
#    but WITHOUT ANY WARRANTY; without even the implied warranty of
#    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
#    General Public License for more details.
#
#  The full text of the GPL is available at:
#
#                  http://www.gnu.org/licenses/
#*****************************************************************************

cdef extern from "string.h":
    char *strchr(char *str, int ch)

cdef extern from "Python.h":
    object PyString_FromStringAndSize(char *v, Py_ssize_t len)
    int PyList_Append(object list, object item) except -1

import math

def foo(*args, **kwds):
    """
    This is a function for testing that simply returns the arguments and
    keywords passed into it.

    EXAMPLES::

        sage: from sage.misc.parser import foo
        sage: foo(1, 2, a=3)
        ((1, 2), {'a': 3})
    """
    return args, kwds

fuction_map = {
  'foo': foo,
  'sqrt': math.sqrt,
  'sin': math.sin,
  'cos': math.cos,
  'tan': math.tan,
}

cdef enum token_types:
    # leave room for ASCII character tokens such as '+'
    INT = 128
    FLOAT
    NAME
    EOS
    ERROR

    LESS_EQ
    GREATER_EQ
    NOT_EQ
    MATRIX

enum_map = {
  INT:        'INT',
  FLOAT:      'FLOAT',
  NAME:       'NAME',
  EOS:        'EOS',
  ERROR:      'ERROR',
  LESS_EQ:    'LESS_EQ',
  GREATER_EQ: 'GREATER_EQ',
  NOT_EQ:     'NOT_EQ',
  MATRIX:     'MATRIX',
}

def token_to_str(int token):
    """
    For speed reasons, tokens are integers. This function returns a string
    representation of a given token.

    EXAMPLES::

        sage: from sage.misc.parser import Tokenizer, token_to_str
        sage: t = Tokenizer("+ 2")
        sage: token_to_str(t.next())
        '+'
        sage: token_to_str(t.next())
        'INT'
    """
    try:
        return enum_map[token]
    except KeyError:
        return chr(token)


cdef inline bint is_alphanumeric(char c):
    return 'a' <= c <= 'z' or 'A' <= c <= 'Z' or '0' <= c <= '9' or c == '_'

cdef inline bint is_whitespace(char c):
    return (c != 0) & (strchr(" \t\n\r", c) != NULL)


cdef class Tokenizer:
    cdef char *s
    cdef string_obj
    cdef int token
    cdef int pos
    cdef int last_pos

    def __init__(self, s):
        """
        This class takes a string and turns it into a list of tokens for use
        by the parser.

        The tokenizer wraps a string object, to tokenize a different string
        create a new tokenizer.

        EXAMPLES::

            sage: from sage.misc.parser import Tokenizer
            sage: Tokenizer("1.5+2*3^4-sin(x)").test()
            ['FLOAT(1.5)', '+', 'INT(2)', '*', 'INT(3)', '^', 'INT(4)', '-', 'NAME(sin)', '(', 'NAME(x)', ')']

        The single character tokens are given by::

            sage: Tokenizer("+-*/^(),=<>[]{}").test()
            ['+', '-', '*', '/', '^', '(', ')', ',', '=', '<', '>', '[', ']', '{', '}']

        Two-character comparisons accepted are::

            sage: Tokenizer("<= >= != == **").test()
            ['LESS_EQ', 'GREATER_EQ', 'NOT_EQ', '=', '^']

        Integers are strings of 0-9::

            sage: Tokenizer("1 123 9879834759873452908375013").test()
            ['INT(1)', 'INT(123)', 'INT(9879834759873452908375013)']

        Floating point numbers can contain a single decimal point and possibly exponential notation::

            sage: Tokenizer("1. .01 1e3 1.e-3").test()
            ['FLOAT(1.)', 'FLOAT(.01)', 'FLOAT(1e3)', 'FLOAT(1.e-3)']

        Note that negative signs are not attached to the token::

            sage: Tokenizer("-1 -1.2").test()
            ['-', 'INT(1)', '-', 'FLOAT(1.2)']

        Names are alphanumeric sequences not starting with a digit::

            sage: Tokenizer("a a1 _a_24").test()
            ['NAME(a)', 'NAME(a1)', 'NAME(_a_24)']

        Anything else is an error::

            sage: Tokenizer("&@~").test()
            ['ERROR', 'ERROR', 'ERROR']

        No attempt for correctness is made at this stage::

            sage: Tokenizer(") )( 5e5e5").test()
            [')', ')', '(', 'FLOAT(5e5)', 'NAME(e5)']
            sage: Tokenizer("?$%").test()
            ['ERROR', 'ERROR', 'ERROR']
        """
        self.pos = 0
        self.last_pos = 0
        self.s = s
        self.string_obj = s # so it doesn't get deallocated before self

    def test(self):
        """
        This is a utility function for easy testing of the tokenizer.

        Destructively read off the tokens in self, returning a list of string
        representations of the tokens.

        EXAMPLES::

            sage: from sage.misc.parser import Tokenizer
            sage: t = Tokenizer("a b 3")
            sage: t.test()
            ['NAME(a)', 'NAME(b)', 'INT(3)']
            sage: t.test()
            []
        """
        all = []
        cdef int token = self.next()
        while token != EOS:
            if token in [INT, FLOAT, NAME]:
                all.append("%s(%s)" % (token_to_str(token), self.last_token_string()))
            else:
                all.append(token_to_str(token))
            token = self.next()
        return all

    cpdef reset(self, int pos = 0):
        """
        Reset the tokenizer to a given position.

        EXAMPLES::

            sage: from sage.misc.parser import Tokenizer
            sage: t = Tokenizer("a+b*c")
            sage: t.test()
            ['NAME(a)', '+', 'NAME(b)', '*', 'NAME(c)']
            sage: t.test()
            []
            sage: t.reset()
            sage: t.test()
            ['NAME(a)', '+', 'NAME(b)', '*', 'NAME(c)']
            sage: t.reset(3)
            sage: t.test()
            ['*', 'NAME(c)']

        No care is taken to make sure we don't jump in the middle of a token::

            sage: t = Tokenizer("12345+a")
            sage: t.test()
            ['INT(12345)', '+', 'NAME(a)']
            sage: t.reset(2)
            sage: t.test()
            ['INT(345)', '+', 'NAME(a)']
        """
        self.pos = self.last_pos = pos

    cdef int find(self) except -1:
        """
        This function actually does all the work, and extensively is tested above.
        """
        cdef bint seen_exp, seen_decimal
        cdef int type
        cdef char* s = self.s
        cdef int pos = self.pos

        # skip whitespace
        if is_whitespace(s[pos]):
            while is_whitespace(s[pos]):
                pos += 1
            self.pos = pos

        # end of string
        if s[pos] == 0:
            return EOS

        # dipthongs
        if s[pos+1] == '=':
            if s[pos] == '<':
                self.pos += 2
                return LESS_EQ
            elif s[pos] == '>':
                self.pos += 2
                return GREATER_EQ
            elif s[pos] == '!':
                self.pos += 2
                return NOT_EQ
            elif s[pos] == '=':
                self.pos += 2
                return '='

        elif s[pos] == '*' and s[pos+1] == '*':
            self.pos += 2
            return '^'

        # simple tokens
        if strchr("+-*/^()=<>,[]{}!", s[pos]):
            type = s[pos]
            self.pos += 1
            return type

        # numeric literals
        if '0' <= s[pos] <= '9' or s[pos] == '.':
            type = INT
            seen_exp = False
            seen_decimal = False
            while True:
                if '0' <= s[pos] <= '9':
                    pass
                elif s[pos] == '.':
                    if seen_decimal or seen_exp:
                        self.pos = pos
                        return type
                    else:
                        type = FLOAT
                        seen_decimal = True
                elif s[pos] == 'e' or s[pos] == 'E':
                    if seen_exp:
                        self.pos = pos
                        return type
                    else:
                        type = FLOAT
                        seen_exp = True
                elif s[pos] == '+' or s[pos] == '-':
                    if not (seen_exp and (s[pos-1] == 'e' or s[pos-1] == 'E')):
                        self.pos = pos
                        return type
                else:
                    self.pos = pos
                    return type
                pos += 1

        # name literals
        if is_alphanumeric(s[pos]):
            while is_alphanumeric(s[pos]):
                pos += 1
            # matrices
            if s[self.pos:pos] == b'matrix':
                self.pos = pos
                return MATRIX
            self.pos = pos
            return NAME

        pos += 1
        self.pos = pos
        return ERROR

    cpdef int next(self):
        """
        Returns the next token in the string.

        EXAMPLES::

            sage: from sage.misc.parser import Tokenizer, token_to_str
            sage: t = Tokenizer("a+3")
            sage: token_to_str(t.next())
            'NAME'
            sage: token_to_str(t.next())
            '+'
            sage: token_to_str(t.next())
            'INT'
            sage: token_to_str(t.next())
            'EOS'
        """
        while is_whitespace(self.s[self.pos]):
            self.pos += 1
        self.last_pos = self.pos
        self.token = self.find()
        return self.token

    cpdef int last(self):
        """
        Returns the last token seen.

        EXAMPLES::

            sage: from sage.misc.parser import Tokenizer, token_to_str
            sage: t = Tokenizer("3a")
            sage: token_to_str(t.next())
            'INT'
            sage: token_to_str(t.last())
            'INT'
            sage: token_to_str(t.next())
            'NAME'
            sage: token_to_str(t.last())
            'NAME'
        """
        return self.token

    cpdef int peek(self):
        """
        Returns the next token that will be encountered, without changing
        the state of self.

        EXAMPLES::

            sage: from sage.misc.parser import Tokenizer, token_to_str
            sage: t = Tokenizer("a+b")
            sage: token_to_str(t.peek())
            'NAME'
            sage: token_to_str(t.next())
            'NAME'
            sage: token_to_str(t.peek())
            '+'
            sage: token_to_str(t.peek())
            '+'
            sage: token_to_str(t.next())
            '+'
        """
        cdef int save_pos = self.pos
        cdef int token = self.find()
        self.pos = save_pos
        return token

    cpdef bint backtrack(self) except -2:
        """
        Put self in such a state that the subsequent call to next() will
        return the same as if next() had not been called.

        Currently, one can only backtrack once.

        EXAMPLES::

            sage: from sage.misc.parser import Tokenizer, token_to_str
            sage: t = Tokenizer("a+b")
            sage: token_to_str(t.next())
            'NAME'
            sage: token_to_str(t.next())
            '+'
            sage: t.backtrack()   # the return type is bint for performance reasons
            False
            sage: token_to_str(t.next())
            '+'
        """
        if self.pos == self.last_pos and self.token != EOS:
            raise NotImplementedError("Can only backtrack once.")
        else:
            self.pos = self.last_pos
            self.token = 0

    cpdef last_token_string(self):
        """
        Return the actual contents of the last token.

        EXAMPLES::

            sage: from sage.misc.parser import Tokenizer, token_to_str
            sage: t = Tokenizer("a - 1e5")
            sage: token_to_str(t.next())
            'NAME'
            sage: t.last_token_string()
            'a'
            sage: token_to_str(t.next())
            '-'
            sage: token_to_str(t.next())
            'FLOAT'
            sage: t.last_token_string()
            '1e5'
        """
        return PyString_FromStringAndSize(&self.s[self.last_pos], self.pos-self.last_pos)


cdef class Parser:

    cdef integer_constructor
    cdef float_constructor
    cdef variable_constructor
    cdef callable_constructor
    cdef bint implicit_multiplication

    def __init__(self, make_int=int, make_float=float, make_var=str, make_function={}, bint implicit_multiplication=True):
        """
        Create a symbolic expression parser.

        INPUT:

        - make_int      -- callable object to construct integers from strings (default int)
        - make_float    -- callable object to construct real numbers from strings (default float)
        - make_var      -- callable object to construct variables from strings (default str)
          this may also be a dictionary of variable names
        - make_function -- callable object to construct callable functions from strings
          this may also be a dictionary
        - implicit_multiplication -- whether or not to accept implicit multiplication

        OUTPUT:

            The evaluated expression tree given by the string, where the above
            functions are used to create the leaves of this tree.

        EXAMPLES::

            sage: from sage.misc.parser import Parser
            sage: p = Parser()
            sage: p.parse("1+2")
            3
            sage: p.parse("1+2 == 3")
            True

            sage: p = Parser(make_var=var)
            sage: p.parse("a*b^c - 3a")
            a*b^c - 3*a

            sage: R.<x> = QQ[]
            sage: p = Parser(make_var = {'x': x })
            sage: p.parse("(x+1)^5-x")
            x^5 + 5*x^4 + 10*x^3 + 10*x^2 + 4*x + 1
            sage: p.parse("(x+1)^5-x").parent() is R
            True

            sage: p = Parser(make_float=RR, make_var=var, make_function={'foo': (lambda x: x*x+x)})
            sage: p.parse("1.5 + foo(b)")
            b^2 + b + 1.50000000000000
            sage: p.parse("1.9").parent()
            Real Field with 53 bits of precision
        """
        self.integer_constructor = make_int
        self.float_constructor = make_float
        if not callable(make_var):
            make_var = LookupNameMaker(make_var)
        if not callable(make_function):
            make_function = LookupNameMaker(make_function)
        self.variable_constructor = make_var
        self.callable_constructor = make_function
        self.implicit_multiplication = implicit_multiplication

    cpdef parse(self, s, bint accept_eqn=True):
        """
        Parse the given string.

        EXAMPLES::

            sage: from sage.misc.parser import Parser
            sage: p = Parser(make_var=var)
            sage: p.parse("E = m c^2")
            E == c^2*m
        """
        cdef Tokenizer tokens = Tokenizer(s)
        if tokens.peek() == MATRIX:
            tokens.next()
            expr = self.p_matrix(tokens)
        else:
            expr = self.p_eqn(tokens) if accept_eqn else self.p_expr(tokens)

        if tokens.next() != EOS:
            self.parse_error(tokens)
        return expr

    cpdef parse_expression(self, s):
        """
        Parse an expression.

        EXAMPLES::

            sage: from sage.misc.parser import Parser
            sage: p = Parser(make_var=var)
            sage: p.parse_expression('a-3b^2')
            -3*b^2 + a
        """
        cdef Tokenizer tokens = Tokenizer(s)
        expr = self.p_expr(tokens)
        if tokens.next() != EOS:
            self.parse_error(tokens)
        return expr

    cpdef parse_sequence(self, s):
        """
        Parse a (possibly nested) set of lists and tuples.

        EXAMPLES::

            sage: from sage.misc.parser import Parser
            sage: p = Parser(make_var=var)
            sage: p.parse_sequence("1,2,3")
            [1, 2, 3]
            sage: p.parse_sequence("[1,2,(a,b,c+d)]")
            [1, 2, (a, b, c + d)]
            sage: p.parse_sequence("13")
            13
        """
        cdef Tokenizer tokens = Tokenizer(s)
        all = self.p_sequence(tokens)
        if tokens.next() != EOS:
            self.parse_error(tokens)
        if len(all) == 1 and isinstance(all, list):
            all = all[0]
        return all

    cpdef p_matrix(self, Tokenizer tokens):
        """
        Parse a matrix

        EXAMPLES::

            sage: from sage.misc.parser import Parser, Tokenizer
            sage: p = Parser(make_var=var)
            sage: p.p_matrix(Tokenizer("([a,0],[0,a])"))
            [a 0]
            [0 a]
        """
        cdef int token
        all = []
        if tokens.next() == '(':
            token = ','
            while token == ',':
                all.append(self.p_list(tokens))
                token = tokens.next()

            if token == ')':
                from sage.matrix.constructor import matrix
                return matrix(all)
            else:
                self.parse_error(tokens, "Malformed matrix")
        else:
            self.parse_error(tokens, "Malformed matrix")

    cpdef p_sequence(self, Tokenizer tokens):
        """
        Parse a (possibly nested) set of lists and tuples.

        EXAMPLES::

            sage: from sage.misc.parser import Parser, Tokenizer
            sage: p = Parser(make_var=var)
            sage: p.p_sequence(Tokenizer("[1+2,0]"))
            [[3, 0]]
            sage: p.p_sequence(Tokenizer("(1,2,3) , [1+a, 2+b, (3+c), (4+d,)]"))
            [(1, 2, 3), [a + 1, b + 2, c + 3, (d + 4,)]]
        """
        all = []
        cdef int token = ','
        while token == ',':
            token = tokens.peek()
            if token == MATRIX:
                tokens.next()
                obj = self.p_matrix(tokens)
            elif token == INT:
                # we optimize for this rather than going all the way to atom
                tokens.next()
                if tokens.peek() == c',':
                    obj = self.integer_constructor(tokens.last_token_string())
                else:
                    tokens.backtrack()
                    obj = self.p_eqn(tokens)
            elif token == '[':
                obj = self.p_list(tokens)
            elif token == '(':
                obj = self.p_tuple(tokens)
            elif token == EOS:
                return all
            elif token == ']' or token == ')':
                tokens.token = ','
                return all
            else:
                obj = self.p_eqn(tokens)
            PyList_Append(all, obj)
            token = tokens.next()

        tokens.backtrack()
        return all

    cpdef p_list(self, Tokenizer tokens):
        """
        Parse a list of items.

        EXAMPLES::

            sage: from sage.misc.parser import Parser, Tokenizer
            sage: p = Parser(make_var=var)
            sage: p.p_list(Tokenizer("[1+2, 1e3]"))
            [3, 1000.0]
            sage: p.p_list(Tokenizer("[]"))
            []
        """
        cdef int token = tokens.next()
        if token != '[':
            self.parse_error(tokens, "Malformed list")
        all = self.p_sequence(tokens)
        token = tokens.next()
        if token != ']':
            self.parse_error(tokens, "Malformed list")
        return all

    cpdef p_tuple(self, Tokenizer tokens):
        """
        Parse a tuple of items.

        EXAMPLES::

            sage: from sage.misc.parser import Parser, Tokenizer
            sage: p = Parser(make_var=var)
            sage: p.p_tuple(Tokenizer("( (), (1), (1,), (1,2), (1,2,3), (1+2)^2, )"))
            ((), 1, (1,), (1, 2), (1, 2, 3), 9)
        """
        cdef int start = tokens.pos
        cdef int token = tokens.next()
        cdef bint real_tuple = True
        if token != '(':
            self.parse_error(tokens, "Malformed tuple")
        all = self.p_sequence(tokens)
        if len(all) == 1:
            if tokens.last() != c',':
                real_tuple = False
        token = tokens.next()
        if token != ')':
            self.parse_error(tokens, "Malformed tuple")
        if real_tuple:
            return tuple(all)
        else:
            token = tokens.peek()
            if token == ',' or token == EOS:
                return all[0]
            else:
                # we have to reparse the entire thing as an expression
                tokens.reset(start)
                return self.p_eqn(tokens)

# eqn ::= expr op expr | expr
    cpdef p_eqn(self, Tokenizer tokens):
        """
        Parse an equation or expression.

        This is the top-level node called by the \code{parse} function.

        EXAMPLES::

            sage: from sage.misc.parser import Parser, Tokenizer
            sage: p = Parser(make_var=var)
            sage: p.p_eqn(Tokenizer("1+a"))
            a + 1

            sage: p.p_eqn(Tokenizer("a == b"))
            a == b
            sage: p.p_eqn(Tokenizer("a < b"))
            a < b
            sage: p.p_eqn(Tokenizer("a > b"))
            a > b
            sage: p.p_eqn(Tokenizer("a <= b"))
            a <= b
            sage: p.p_eqn(Tokenizer("a >= b"))
            a >= b
            sage: p.p_eqn(Tokenizer("a != b"))
            a != b
        """
        lhs = self.p_expr(tokens)
        cdef int op = tokens.next()
        if op == '=':
            return lhs == self.p_expr(tokens)
        elif op == NOT_EQ:
            return lhs != self.p_expr(tokens)
        elif op == '<':
            return lhs < self.p_expr(tokens)
        elif op == LESS_EQ:
            return lhs <= self.p_expr(tokens)
        elif op == '>':
            return lhs > self.p_expr(tokens)
        elif op == GREATER_EQ:
            return lhs >= self.p_expr(tokens)
        else:
            tokens.backtrack()
            return lhs

# expr ::=  term | expr '+' term | expr '-' term
    cpdef p_expr(self, Tokenizer tokens):
        """
        Parse a list of one or more terms.

        EXAMPLES::

            sage: from sage.misc.parser import Parser, Tokenizer
            sage: p = Parser(make_var=var)
            sage: p.p_expr(Tokenizer("a+b"))
            a + b
            sage: p.p_expr(Tokenizer("a"))
            a
            sage: p.p_expr(Tokenizer("a - b + 4*c - d^2"))
            -d^2 + a - b + 4*c
            sage: p.p_expr(Tokenizer("a - -3"))
            a + 3
            sage: p.p_expr(Tokenizer("a + 1 == b"))
            a + 1
        """
        # Note: this is left-recursive, so we can't just recurse
        cdef int op
        operand1 = self.p_term(tokens)
        op = tokens.next()
        while op == '+' or op == '-':
            operand2 = self.p_term(tokens)
            if op == '+':
                operand1 = operand1 + operand2
            else:
                operand1 = operand1 - operand2
            op = tokens.next()
        tokens.backtrack()
        return operand1

# term ::=  factor | term '*' factor | term '/' factor
    cpdef p_term(self, Tokenizer tokens):
        """
        Parse a single term (consisting of one or more factors).

        EXAMPLES::

            sage: from sage.misc.parser import Parser, Tokenizer
            sage: p = Parser(make_var=var)
            sage: p.p_term(Tokenizer("a*b"))
            a*b
            sage: p.p_term(Tokenizer("a * b / c * d"))
            a*b*d/c
            sage: p.p_term(Tokenizer("-a * b + c"))
            -a*b
            sage: p.p_term(Tokenizer("a*(b-c)^2"))
            a*(b - c)^2
            sage: p.p_term(Tokenizer("-3a"))
            -3*a
        """
        # Note: this is left-recursive, so we can't just recurse
        cdef int op
        operand1 = self.p_factor(tokens)
        op = tokens.next()
        if op == NAME and self.implicit_multiplication:
            op = '*'
            tokens.backtrack()
        while op == '*' or op == '/':
            operand2 = self.p_factor(tokens)
            if op == '*':
                operand1 = operand1 * operand2
            else:
                operand1 = operand1 / operand2
            op = tokens.next()
            if op == NAME and self.implicit_multiplication:
                op = '*'
                tokens.backtrack()
        tokens.backtrack()
        return operand1

# factor ::=  '+' factor | '-' factor | power
    cpdef p_factor(self, Tokenizer tokens):
        """
        Parse a single factor, which consists of any number of unary +/-
        and a power.

        EXAMPLES::

            sage: from sage.misc.parser import Parser, Tokenizer
            sage: R.<t> = ZZ[['t']]
            sage: p = Parser(make_var={'t': t})
            sage: p.p_factor(Tokenizer("- -t"))
            t
            sage: p.p_factor(Tokenizer("- + - -t^2"))
            -t^2
            sage: p.p_factor(Tokenizer("t^11 * x"))
            t^11
        """
        cdef int token = tokens.next()
        if token == '+':
            return self.p_factor(tokens)
        elif token == '-':
            return -self.p_factor(tokens)
        else:
            tokens.backtrack()
            return self.p_power(tokens)

# power ::=  (atom | atom!) ^ factor | atom | atom!
    cpdef p_power(self, Tokenizer tokens):
        """
        Parses a power. Note that exponentiation groups right to left.

        EXAMPLES::

            sage: from sage.misc.parser import Parser, Tokenizer
            sage: R.<t> = ZZ[['t']]
            sage: p = Parser(make_var={'t': t})
            sage: p.p_factor(Tokenizer("-(1+t)^-1"))
            -1 + t - t^2 + t^3 - t^4 + t^5 - t^6 + t^7 - t^8 + t^9 - t^10 + t^11 - t^12 + t^13 - t^14 + t^15 - t^16 + t^17 - t^18 + t^19 + O(t^20)
            sage: p.p_factor(Tokenizer("t**2"))
            t^2
            sage: p.p_power(Tokenizer("2^3^2")) == 2^9
            True

            sage: p = Parser(make_var=var)
            sage: p.p_factor(Tokenizer('x!'))
            factorial(x)
            sage: p.p_factor(Tokenizer('(x^2)!'))
            factorial(x^2)
            sage: p.p_factor(Tokenizer('x!^2'))
            factorial(x)^2

        """
        operand1 = self.p_atom(tokens)
        cdef int token = tokens.next()
        if token == '^':
            operand2 = self.p_factor(tokens)
            return operand1 ** operand2
        elif token == "!":
            from sage.functions.all import factorial
            operand1 = factorial(operand1)
            if tokens.peek() == '^':
                tokens.next()
                operand2 = self.p_factor(tokens)
                return operand1 ** operand2
            else:
                return operand1
        else:
            tokens.backtrack()
            return operand1

# atom ::= int | float | name | '(' expr ')' | name '(' args ')'
    cpdef p_atom(self, Tokenizer tokens):
        """
        Parse an atom. This is either a parenthesized expression, a function call, or a literal name/int/float.

        EXAMPLES::

            sage: from sage.misc.parser import Parser, Tokenizer
            sage: p = Parser(make_var=var, make_function={'sin': sin})
            sage: p.p_atom(Tokenizer("1"))
            1
            sage: p.p_atom(Tokenizer("12"))
            12
            sage: p.p_atom(Tokenizer("12.5"))
            12.5
            sage: p.p_atom(Tokenizer("(1+a)"))
            a + 1
            sage: p.p_atom(Tokenizer("(1+a)^2"))
            a + 1
            sage: p.p_atom(Tokenizer("sin(1+a)"))
            sin(a + 1)
            sage: p = Parser(make_var=var, make_function={'foo': sage.misc.parser.foo})
            sage: p.p_atom(Tokenizer("foo(a, b, key=value)"))
            ((a, b), {'key': value})
            sage: p.p_atom(Tokenizer("foo()"))
            ((), {})
        """
        cdef int token = tokens.next()
        if token == INT:
            return self.integer_constructor(tokens.last_token_string())
        elif token == FLOAT:
            return self.float_constructor(tokens.last_token_string())
        elif token == NAME:
            name = tokens.last_token_string()
            token = tokens.next()
            if token == '(':
                func = self.callable_constructor(name)
                args, kwds = self.p_args(tokens)
                token = tokens.next()
                if token != ')':
                    self.parse_error(tokens, "Bad function call")
                return func(*args, **kwds)
            else:
                tokens.backtrack()
                return self.variable_constructor(name)
        elif token == '(':
            expr = self.p_expr(tokens)
            token = tokens.next()
            if token != ')':
                self.parse_error(tokens, "Mismatched parentheses")
            return expr
        else:
            self.parse_error(tokens)

# args = arg (',' arg)* | EMPTY
    cpdef p_args(self, Tokenizer tokens):
        """
        Returns a list, dict pair.

        EXAMPLES::

            sage: from sage.misc.parser import Parser, Tokenizer
            sage: p = Parser()
            sage: p.p_args(Tokenizer("1,2,a=3"))
            ([1, 2], {'a': 3})
            sage: p.p_args(Tokenizer("1, 2, a = 1+5^2"))
            ([1, 2], {'a': 26})
        """
        args = []
        kwds = {}
        if tokens.peek() == ')':
            return args, kwds
        cdef int token = ','
        while token == ',':
            arg = self.p_arg(tokens)
            if isinstance(arg, tuple):
                name, value = arg
                kwds[name] = value
            else:
                args.append(arg)
            token = tokens.next()
        tokens.backtrack()
        return args, kwds

# arg = expr | name '=' expr
    cpdef p_arg(self, Tokenizer tokens):
        """
        Returns an expr, or a (name, expr) tuple corresponding to a single
        function call argument.

        EXAMPLES:

        Parsing a normal expression::

            sage: from sage.misc.parser import Parser, Tokenizer
            sage: p = Parser(make_var=var)
            sage: p.p_arg(Tokenizer("a+b"))
            a + b

       A keyword expression argument::

            sage: from sage.misc.parser import Parser, Tokenizer
            sage: p = Parser(make_var=var)
            sage: p.p_arg(Tokenizer("val=a+b"))
            ('val', a + b)

        A lone list::

            sage: from sage.misc.parser import Parser, Tokenizer
            sage: p = Parser(make_var=var)
            sage: p.p_arg(Tokenizer("[x]"))
            [x]

        """
        cdef int token = tokens.next()
        if token == NAME and tokens.peek() == '=':
            name = tokens.last_token_string()
            tokens.next()
            return name, self.p_expr(tokens)
        if token == "[" :
            tokens.backtrack()
            return self.p_list(tokens)
        else:
            tokens.backtrack()
            return self.p_expr(tokens)

    cdef parse_error(self, Tokenizer tokens, msg="Malformed expression"):
        raise SyntaxError(msg, tokens.s, tokens.pos)


cdef class LookupNameMaker:
    cdef object names
    cdef object fallback
    def __init__(self, names, fallback=None):
        """
        This class wraps a dictionary as a callable for use in creating names.
        It takes a dictionary of names, and an (optional) callable to use
        when the given name is not found in the dictionary.

        EXAMPLES::

            sage: from sage.misc.parser import LookupNameMaker
            sage: maker = LookupNameMaker({'pi': pi}, var)
            sage: maker('pi')
            pi
            sage: maker('pi') is pi
            True
            sage: maker('a')
            a
        """
        self.names = names
        self.fallback = fallback

    def __call__(self, name):
        """
        TESTS::

            sage: from sage.misc.parser import LookupNameMaker
            sage: maker = LookupNameMaker({'a': x}, str)
            sage: maker('a')
            x
            sage: maker('a') is x
            True
            sage: maker('b')
            'b'
        """
        try:
            return self.names[name]
        except KeyError:
            if self.fallback is not None:
                return self.fallback(name)
            raise NameError("Unknown variable: '{}'".format(name))

