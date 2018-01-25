#cython: cdivision = True
#cython: embedsignature = True
import sys
# from libc.stdint cimport uint64_t
import random
ctypedef unsigned long long int64
ctypedef int64 int128
ctypedef int128 move
ctypedef int128 bitboard

from numpy.math cimport INFINITY
cdef double INF=INFINITY
    
'''
bitboards for the board represented by which bit (example is 6x7 board)
0  0  0  0  0  0  0
5 12 19 26 33 40 47
4 11 18 25 32 39 46
3 10 17 24 31 38 45
2  9 16 23 30 37 44
1  8 15 22 29 36 43
0  7 14 21 28 35 42
'''

cdef enum:
    MAX_ROWS = 16
    MAX_COLUMNS = 16
    

cdef int ROWS = 6
cdef int COLUMNS = 7
cdef int COL_MASK = (1 << (ROWS+1))-1
cdef int *DeBruijn = [0,1,28,2,29,14,24,3,30,22,20,15,25,17,4,8,31,27,13,23,21,19,16,7,26,12,18,6,11,5,10,9]
random.seed(42)
cdef unsigned long long hash_table[2][128]
hash_table = get_zob()

cdef int population(bitboard bb):
    #counts the number of on bits in the bitboard
    cdef int pop = 0    
    while bb:
        pop += 1
        bb &= (bb -1)
    return pop

cdef unsigned int bitindex(move bitmove): #DeBruijn method by multiply and lookup
    return DeBruijn[<unsigned long> (bitmove * <move> 0x077CB531) >> 27]

cdef int log(bitboard v): #binary method for finding log
    cdef int64 b[6]
    cdef int64 S[6]
    b = [0x2, 0xC, 0xF0, 0xFF00, 0xFFFF0000, 0xFFFFFFFF00000000]
    S = [1, 2, 4, 8, 16, 32]
    cdef int i=5
    cdef int r = 0
    while i >= 0:   
        if v & b[i]:
            v >>= S[i]
            r |= S[i]   
        i -= 1
    return r
    

cdef void insert(int* scores, move* moves, int current, move bitmove, int size):
    cdef int i,j
    i = 0
    while current <= scores[i] and i < size: #find the index to insert
        i += 1
    while size > i: 
        scores[size] = scores[size-1]
        moves[size]  = moves[size-1]
        size -= 1
    scores[i] = current
    moves[i] = bitmove

cdef get_zob():
    cdef:
        unsigned long long zob[2][128]
        int i,j
    for i in range(2):
        for j in range(128):
            zob[i][j] = random.getrandbits(64)
    return zob

# cdef class Score(object):
#     cdef:
#         public double result
#         public int depth
        
#     def __cinit__(self,double result=0,int depth=0):
#         self.result = result
#         self.depth = depth
#     def __lt__(self,other):
#         if self.result != other.result:
#             return self.result < other.result
#         else:
#             return self.depth * self.result > other.depth * self.result
#     def __gt__(self,other):
#         return other < self
#     def __le__(self,other):
#         if self.result != other.result:
#             return self.result < other.result
#         else:
#             return self.depth * self.result >= other.depth * self.result
#     def __ge__(self,other):
#         return other <= self
#     def __eq__(self,other):
#         return self.result==other.result and self.depth==other.depth
#     def __ne__(self,other):
#         return not self==other
#     def __neg__(self):
#         self.result *= -1
    

cdef class Board(object):
    
    cdef public:
        int player,value,rows,columns,over,result
        object log
        int height[64]
        bitboard boards[2],bitlog[MAX_COLUMNS * MAX_ROWS]
        bitboard up,up2,up3,down,down2,down3,vert,vert2,vert3,hor,hor2,hor3,MASK,BOTTOM
        bitboard key
        int64 nodes_visited
        int clog[MAX_COLUMNS * MAX_ROWS]
        int ilog
        int strong

        
        
    def __cinit__(self,int rows = 6,int columns = 7):
        global ROWS
        global COLUMNS
        global COL_MASK
        ROWS = rows
        COLUMNS = columns
        if COLUMNS*(ROWS+1)> 64:
            sys.exit('dimensions too large for 64-bit boards')
        COL_MASK = (<bitboard>1 << <bitboard> (ROWS+1))-1
        cdef move i,bitmove
        self.player = 0
        self.value = 1
        self.log = []
        self.over = 0
        self.result = 0
        self.rows = rows
        self.columns = columns
        self.key = 0
        self.ilog = 0
        self.nodes_visited = 0
        
        self.boards = [0,0]
        self.up = ROWS + 2
        self.up2 = self.up*2 #seeing if only doing this calculation once speeds things up
        self.up3 = self.up*3
        
        self.down = ROWS
        self.down2 = self.down*2
        self.down3 = self.down*3
        
        self.vert = 1
        self.vert2 = self.vert*2
        self.vert3 = self.vert*3
        
        self.hor = ROWS + 1
        self.hor2 = self.hor*2
        self.hor3 = self.hor*3
    
        self.BOTTOM = 0
        self.MASK = 0
            
        for i in xrange(COLUMNS):
            self.BOTTOM |= <bitboard> 1 << i * <bitboard>(ROWS + 1)
        for i in xrange(ROWS):
            self.MASK |= self.BOTTOM << i
            

            
        
        
# keeps track of how many pieces are in each column

    cdef int check_win(self, int player):
        cdef bitboard bb = self.boards[player]
        if     (bb & (bb>>self.vert) & (bb>>self.vert2) & (bb>>self.vert3) |
                bb & (bb>>self.hor)  & (bb>>self.hor2)  & (bb>>self.hor3)  |
                bb & (bb>>self.up)   & (bb>>self.up2)   & (bb>>self.up3)   |
                bb & (bb>>self.down) & (bb>>self.down2) & (bb>>self.down3)):
            return 1
        return 0
    
    cpdef is_key(self,key):
        return self.get_key() == key
    
    cdef bitboard get_key(self):
        return self.boards[0] | ((self.boards[0]|self.boards[1])+self.BOTTOM)
    
    cdef bitboard get_symm_keys(self,bitboard* keys):        
        cdef bitboard COL_MASK = (<bitboard> 1 << (ROWS+<bitboard>1))-<bitboard>1
        cdef int i
        keys[0] = self.get_key()   
        keys[1] = 0
        for i in xrange(COLUMNS):
            keys[1] ^= (COL_MASK & (keys[0] >> ((ROWS+<bitboard>1) * <bitboard>i))) << (
                (ROWS+<bitboard>1)*(COLUMNS-<bitboard>(i+1)))
        return 1 + (keys[0] != keys[1])
    
    cpdef get_key_wrapper(self):
        return self.get_key()        
    cdef int check_full(self):
        return self.boards[0]|self.boards[1] == self.MASK
    
    cdef int check_over(self):
        return self.check_win(0) or self.check_win(1) or self.check_full()   
    
    cdef double get_score(self):
        if self.check_win(0):
            return self.rows*self.columns - self.ilog + 1
        if self.check_win(1):
            return -(self.rows*self.columns - self.ilog + 1)
        return 0   
    
    cdef double max_score(self,int n): #winning next move  
        #the int n is just for communicating with move generator. There is probably a more transparent way of doing this
        return max(0,self.rows*self.columns - self.ilog + 1 - n)
        
    cdef double min_score(self,int n): #losing in n plies
        return min(0,-(self.rows*self.columns - self.ilog + 1 - n))
        
    cdef int next_turn_result(self):
        cdef bitboard bitmap = self.get_legal_bitmap()
        if bitmap == -1:
            return 1
        if bitmap == 0:
            return -1
        return 0
        
        
    cdef int move_score(self,move bitmove, int player):
        
        # A simple heuristic for move ordering
        # return the number of winning moves on the board after moving to move, minus the losing moves.
        
        cdef bitboard p1,p2,wins,legal,legalwins
        
        if player == 0:
            p1 = self.boards[0] ^ bitmove
            p2 = self.boards[1]
        else:
            p1 = self.boards[0]
            p2 = self.boards[1] ^ bitmove
            
        #check if there is a 2-way threat
        wins = self.winning_plays(p1,p2,player)
        legal = (p1|p2) + self.BOTTOM
        legalwins = wins & legal 
        # check if board has unblockable win (2-way or stacked threats)
        if ((legalwins) & (legalwins-1)) or (legalwins & (wins >> <bitboard> 1)): 
            return 128 #signal a win
        else:
            return population(wins)
        
    cdef bitboard winning_plays(self,bitboard p1,bitboard p2,int player):
        #bitboard argument for the case that you want to check boards other than the current board state
        #13 patterns to check for 4 each for horizonal, ldiagonal and rdiagonal, as well as one vertical
        #going to check which places win the game, then remove moves that have already been played with self.MASK
        cdef bitboard holder, winners,bb
        if player == 0:
            bb = p1
        else:
            bb = p2
        winners = 0
        
        #vertical
        winners |= (bb << self.vert) & (bb << self.vert2) & (bb << self.vert3)
        
        #horizontal
        #can do two patterns at a time with an intermitant bitboard
        holder = (bb << self.hor) & (bb << self.hor2) # xx_
        winners |= holder & (bb << self.hor3) #xxx_
        winners |= holder & (bb >> self.hor) # xx_x
        holder = (bb >> self.hor) & (bb >> self.hor2) # _xx
        winners |= holder & (bb >> self.hor3) #_xxx
        winners |= holder & (bb << self.hor) # x_xx
        
        #similarly for the diagonals
        holder = (bb << self.up) & (bb << self.up2) # xx_
        winners |= holder & (bb << self.up3) #xxx_
        winners |= holder & (bb >> self.up) # xx_x
        holder = (bb >> self.up) & (bb >> self.up2) # _xx
        winners |= holder & (bb >> self.up3) #_xxx
        winners |= holder & (bb << self.up) # x_xx
        
        holder = (bb << self.down) & (bb << self.down2) # xx_
        winners |= holder & (bb << self.down3) #xxx_
        winners |= holder & (bb >> self.down) # xx_x
        holder = (bb >> self.down) & (bb >> self.down2) # _xx
        winners |= holder & (bb >> self.down3) #_xxx
        winners |= holder & (bb << self.down) # x_xx

        winners &= (self.MASK^(p1|p2)) #only empty, legal squares are wanted
        
        return winners
    
    cdef bitboard get_legal_bitmap(self):
        cdef bitboard legal , winning , bitmove , bb , viable , blocking
        cdef int col , i, num_moves,value
        cdef int scores[MAX_COLUMNS]
        
        legal = ((self.boards[0]|self.boards[1]) + self.BOTTOM) & self.MASK
        winning = self.winning_plays(self.boards[0],self.boards[1],self.player)
        bb = legal&winning #is there a winning move 
        if bb:
            return -1

        blocking = self.winning_plays(self.boards[0],self.boards[1],self.player^1) #opponent's winning moves
        bb = legal&blocking #do we need to block a win?

        if bb:
            if bb & (blocking >> <bitboard> 1) or (bb & (bb -1)): 
# bb&(bb-1) removes the least significant bit, which evaluates to true only when there is more than one bit set
# if there are two stacked wins or two playable wins
                return 0
            return bb
        viable = legal & ~(blocking >> <bitboard> 1) #don't consider moves which let the opponent win
        return viable
        
        
    cdef int get_legal_smart(self,move* moves):
        #return the number of moves sent back
        #flaged -1 if win 0 if loss
        #assumes that can't lose on next move
        cdef bitboard legal , winning , bitmove , bb , viable , blocking
        cdef int col , i, num_moves,value
        cdef int scores[MAX_COLUMNS]
        
        legal = ((self.boards[0]|self.boards[1]) + self.BOTTOM) & self.MASK
        blocking = self.winning_plays(self.boards[0],self.boards[1],self.player^1) #opponent's winning moves
        bb = legal&blocking #do we need to block a win?
        if bb:
            moves[0] = bb
            return 1                
        viable = legal & ~(blocking >> <bitboard> 1) #don't consider moves which let the opponent win
        if not viable: #every move loses, return any move
            moves[0] = legal & (~legal + 1)
            return 0
        num_moves = 0
        while viable:
            bitmove = viable & (~viable + 1) #lowest set bit            
            value = self.move_score(bitmove,self.player) # want some separation to add weight to centre
            if value == 128: #sentinal for two way win
                moves[0] = bitmove
                return -3
            col = log(bitmove) / (ROWS+1)
            value *= COLUMNS
            value += min(col , COLUMNS - 1 - col)
            insert(scores,moves,value,bitmove,num_moves)            
            num_moves += 1
            viable ^= bitmove
        return num_moves

    cdef int get_legal_fast(self,move* moves):
        cdef bitboard legal
        cdef move bitmove
        cdef int n
        n=0
        legal = ((self.boards[0]|self.boards[1]) + self.BOTTOM) & self.MASK
        while legal:
            bitmove = legal & (~legal + 1)
            moves[n] = bitmove
            legal ^= bitmove
            n+=1
        return n
    
    cdef int get_legal(self,move* moves):
        return self.get_legal_smart(moves)
            
    cpdef object p_get_legal(self):
        cdef int i
        cdef object l
        l = [COLUMNS/2 + (1 - 2*(i%2))*((i+1)/2) for i in xrange(COLUMNS)] #starting from middle
        return [move for move in l if self.height[move] < ROWS]
    
    cpdef p_update(self,int m):
        self.boards[self.player] ^= (<bitboard> 1) << (m * (1+self.rows) + self.height[m])
        self.key ^= hash_table[self.player][m * (1+self.rows) + self.height[m]]
        self.player ^= 1
        self.height[m] += 1
        self.log.append(m)
        self.clog[self.ilog] = m
        self.bitlog[self.ilog] = (<bitboard> 1) << (m * (1+self.rows) + self.height[m])
        self.ilog += 1
        self.nodes_visited += 1
        
    cdef update(self,move bitmove):
#         assert(not bitmove & (bitmove - 1))
        self.boards[self.player] ^= bitmove
        self.player ^= 1
        self.bitlog[self.ilog] = bitmove
        self.ilog += 1
        self.nodes_visited += 1
        
    cpdef p_erase(self):
        cdef int m
        m = self.log.pop()
        self.ilog -= 1
        self.height[m] -= 1
        self.player ^= 1
        self.key ^= hash_table[self.player][m * (1+self.rows) + self.height[m]]
        self.boards[self.player] ^= (<bitboard> 1) << (m * (1+self.rows) + self.height[m])
        
    cdef erase(self):
        cdef move bitmove
        bitmove = self.bitlog[self.ilog - 1]
        self.ilog -= 1
        self.player ^= 1
        self.boards[self.player] ^= bitmove
        
    def get_nodes_visited(self):
        return self.nodes_visited
        
    def get_boards(self):
        return self.boards
    
    def get_player(self):
        return self.player
    
    def get_log(self):
        return self.log
    
    def get_dimensions(self):
        return self.rows,self.columns
    
    def print_vitals(self):
        print 'boards',self.boards
        print "player's turn" , self.player
        print "column heights", [self.height[i] for i in xrange(self.columns)]
        print "Is the game over?", self.is_over()
        print "who won?", self.result
        print "log", self.log
        print "nodes visited", self.nodes_visited
        print "key", self.key
        print "MASK", self.MASK
        print "ROWS", ROWS
        print "COLUMNS",COLUMNS
    

    cpdef print_board(self):
        cdef int i,j
        big = ''
        for i in xrange(self.rows):
            s = '|'
            for j in xrange(self.columns):
                s += ' '
                if (self.boards[0] >> i + j * (1 + self.rows)) & 1:
                    s += 'x'
                elif (self.boards[1] >> i + j * (1 + self.rows)) & 1:
                    s += 'o'
                else:
                    s += ' '
                s += '|'
            big = s + '\n' + big
        print big
            

    cpdef is_over(self):
        return self.check_over()
    cpdef get_result(self):
        return self.result
    
    
cpdef char_debug():
    cdef char a,b
    a = <char>'n'
    print a
    print a == <char>'n'
    b=<char>'l'
    print b
    print a == b
    print a == <char>'n'