cdef enum:
#     PRIME = 15000017
#     PRIME = 11111119    
    PRIME = 1000003
    
cdef int64 pushes = 0
cdef int64 bigpulls = 0
cdef int64 newpulls = 0
#table will have (key, value, depth, best move, type of node, size of node)
cdef struct position_data:
    bitboard key
    double value
    int depth
    move move
    int64 size
    char node
    
cdef struct twobigentry:
    position_data small
    position_data big    

cdef twobigentry twobig[PRIME]

cdef position_data init_position_data():
    cdef position_data data
    data.key = -1
    data.value = -1
    data.node  = 'n'
    data.depth = -1
    data.move = -1
    data.size = 0
    return data
    
cdef void init_twobig():
    for i in xrange(PRIME):
        twobig[i].small = init_position_data()
        twobig[i].big = init_position_data()
        
cdef push_twobig(int64 key,double score,int128 move,int depth,int128 size,char node):
    cdef int64 index
    cdef int64 temp
    global pushes
    index = key % <int64> PRIME
    pushes = pushes+1

    if key == twobig[index].big.key or size > twobig[index].big.size:
        twobig[index].big.value = score
        twobig[index].big.depth = depth
        twobig[index].big.node = node
        if size > twobig[index].big.size:
            twobig[index].big.size = size
        twobig[index].big.move = move
        twobig[index].big.key = key
        
    else:
        twobig[index].small.value = score
        twobig[index].small.depth = depth
        twobig[index].small.node  = node
        if key != twobig[index].small.key or size > twobig[index].small.size:
            twobig[index].small.size = size
        twobig[index].small.key = key
        twobig[index].small.move = move
            
cdef position_data default
default = init_position_data()
    
#@cython.cdivision(True)
cdef position_data* pull_twobig(int64 key):
    cdef int64 index = key % <int64> PRIME
    if key == twobig[index].big.key:
        return &twobig[index].big
    elif key == twobig[index].small.key:
        return &twobig[index].small
    return &default


cdef int symply = 22
cpdef change_symply(int n):
    global symply
    symply = n

cdef double ab(Board board,int depth, double alpha, double beta,dict book,int ply , int* nodes_visited):
    nodes_visited[0] += 1
    
    if depth == 0:
        return 0
    cdef bitboard thiskey
    thiskey = board.get_key()
    if ply >= 0 and thiskey in book: 
        return book[thiskey]
    

    cdef move moves[MAX_COLUMNS]
    cdef int i,j,t
    cdef int num_legal
    cdef object legal_moves
    cdef int64 rand
    cdef position_data* entry
    cdef int64 size
    cdef int player 
    cdef double best = -INF
    cdef double current = -1
    cdef move candidate = -1
    cdef int passed_score[1]
    cdef move passed_move[1]
    cdef int scores[MAX_COLUMNS]
    cdef double original_alpha = alpha
    cdef double original_beta = beta
    cdef char node = 'n'
    cdef int counter = 0
    cdef int table_move=0
    cdef bitboard keys[MAX_COLUMNS]
    cdef position_data* thisentry
    cdef int n_keys
    cdef int next_turn
        
    
    passed_move[0] = 0
    passed_score[0] = -1
    global pushes
    global d
    global symply
    
    size = nodes_visited[0] #store current visit count to compare to later
    
    # window narrowing
    alpha = max(alpha,board.min_score(2))
    beta = min(beta,board.max_score(1))
    if alpha>=beta:
        return alpha
    
    if board.player == 0:
        player = 1
    else:
        player = -1
    if board.ilog <symply:
        n_keys = board.get_symm_keys(keys)
    else:
        n_keys = 1
        keys[0] = thiskey
    thisentry = pull_twobig(thiskey)

    for i in xrange(n_keys):
        entry = pull_twobig(keys[i])
        if entry[0].node != <char>'n':
            if entry[0].node == 'x':
                return entry[0].value

            if entry[0].depth >= depth:

                if entry[0].node == <char>'e': # if the value is certain, we use it
                    return entry[0].value


                if entry[0].node == <char>'u' and beta > entry[0].value:
                    beta = entry[0].value


                if entry[0].node == <char>'l' and alpha< entry[0].value:
                    alpha = entry[0].value
    
            
# # the move from the transposition talbe should be tried first, since it was the best move earlier in the search
# # This should really just be moved to the first entry in the legal moves list, 
# # but since it will be in the transposition table when it comes up, it doesn't use much time
                   

    best = alpha
    candidate = thisentry[0].move

    if alpha < beta:
            #check if there is a quick win or loss early
        next_turn = board.next_turn_result()
        if next_turn == 1:
            node = <char> 'x'
            size = nodes_visited[0] - size
    #         assert(not moves[0] & (moves[0]-1)),'forced win'
            push_twobig(board.get_key(),board.max_score(1),-1,depth,size+1,node)
            return board.max_score(1)
        if next_turn == -1:
            node = <char> 'x'
            size = nodes_visited[0] - size
    #         assert(not moves[0] & (moves[0]-1)),'inevitable loss'
            push_twobig(board.get_key(),board.min_score(2),-1,depth,size+1,node)
            return board.min_score(2)
        # window narrowing (again)
        alpha = max(alpha,board.min_score(4))
        beta = min(beta,board.max_score(3))
        best = alpha
        
    if alpha < beta:

        num_legal = board.get_legal(moves)
#         num_legal = board.get_legal_fast(moves)

#if the move generator is able to filter bad moves

        if num_legal < 0: #sentinal for forced win in -num_legal plies
            node = <char> 'x'
            size = nodes_visited[0] - size
            assert(not moves[0] & (moves[0]-1)),'forced win'
            push_twobig(board.get_key(),board.max_score(-num_legal),moves[0],depth,size+1,node)
            return board.max_score(-num_legal)
        if num_legal == 0: #sentinal for loss next move
            node = <char> 'x'
            size = nodes_visited[0] - size
            assert(not moves[0] & (moves[0]-1)),'inevitable loss'
            push_twobig(board.get_key(),board.min_score(2),moves[0],depth,size+1,node)
            return board.min_score(2)        
    
        if candidate == -1:
            candidate = moves[0]
        
        if thisentry[0].node == 'l' or thisentry[0].node == 'e': #try best move from earlier attempt first
            table_move = 1 #flag that we tried the table move
            counter += 1
#             assert(thisentry.move in [moves[i] for i in xrange(num_legal)])
            board.update(thisentry[0].move)
            if board.check_over():
                current = board.get_score()*(1-2*board.player)
            else:
                current = - ab(board,depth - 1, - beta , - alpha,book,ply-1,nodes_visited)     
            if current > best:
                best = current
                candidate = thisentry[0].move
            if best > alpha:
                alpha = best
            board.erase()
            
            
        for i in xrange(num_legal):
            if alpha >= beta:
                break                
            if table_move and moves[i] == thisentry[0].move: 
                continue
            counter += 1
            board.update(moves[i])
            if board.check_over():
                current = board.get_score()*(1-2*board.player)
            else:
                current = - ab(board,depth - 1, - beta , - alpha,book,ply-1,nodes_visited)
            if current > best:
                best = current
                candidate = moves[i]
            if best > alpha:
                alpha = best
            board.erase()
            

    size = nodes_visited[0] - size #how many nodes were accessed since this ab function was called
    if best >= original_beta:
        node = <char>'l'
    elif best <= original_alpha:
        node = <char>'u'
    else:
        node = <char>'e'
    push_twobig(board.get_key(),best,candidate,depth,size+1,node)
    return best

cdef double ab_run(Board board,int depth,double alpha,double beta,int iterate,dict book,int ply):
    cdef int d
    cdef int player
    cdef double value
    cdef int nodes_visited = 0
    
    if iterate:
        for d in xrange(depth+1):
            value = ab(board,d,alpha,beta,book,ply,&nodes_visited)
            if value:
                break
    else:
        value = ab(board,depth,alpha,beta,book,ply,&nodes_visited)
    return value

def ab_wrapper(Board board,int depth=0,double alpha=-INF,double beta = INF,int iterate = 0,dict book = {},ply = -1):
    cdef double value
    value = ab_run(board,depth,alpha,beta,iterate,book,ply)
    return value

cdef int64 seed[2]
# seed[1] = 42
seed[1] = random.randint(0,0xffffffffffffffff)

cdef int64 rng():
    return random.getrandbits(64)

# cdef int64 rng():
#     cdef int64 x,y
#     x=seed[0]
#     y=seed[1]
#     seed[0]=y
#     x^=x<<23
#     seed[1]=x^y^(x>>17)^(y>>26)
#     return seed[1]+y

def debug_wrapper():
    count = 0
    i = 0
    cdef char n
    cdef char b
    while i<PRIME and count < 100:
        i +=1
        if twobig[i].big.key != -1 or twobig[i].small.key != -1:
            count += 1
            n = twobig[i].small.node
            b = twobig[i].big.node
            if n == 'n':
                np = 'n'
            elif n == 'x':
                np = 'x'
            elif n == 'u':
                np = 'u'
            elif n == 'l':
                np = 'l'
            elif n == 'e':
                np = 'e'
            else:
                np = 'unknown'
            if b == 'n':
                bp = 'n'
            elif b == 'x':
                bp = 'x'
            elif b == 'u':
                bp = 'u'
            elif b == 'l':
                bp = 'l'
            elif b == 'e':
                bp = 'e'
            else:
                bp = 'unknown'
            print (hex(twobig[i].small.key),twobig[i].small.value,twobig[i].small.depth,hex(twobig[i].small.move),twobig[i].small.size,np)
            print (hex(twobig[i].big.key),twobig[i].big.value,twobig[i].big.depth,hex(twobig[i].big.move),twobig[i].big.size,bp)
    
cpdef int128 key_symm(int128 key):
    cdef int128 new = 0
    for i in xrange(COLUMNS):
        new ^= (COL_MASK & (key >> ((ROWS+1) * i))) << ((ROWS+1)*(COLUMNS-i-1))
    return new

def reset_pulls_pushes():
    global pushes
    global bigpulls
    global newpulls
    pushes = 0
    bigpulls = 0
    newpulls = 0
def pulls_count():
    return newpulls,bigpulls
def pushes_count():
    return pushes
def init_wrapper():
    init_twobig()

    
def print_from_key(key):
    cdef int128 board1 = 0L
    cdef int128 board2 = 0L
    
    for i in xrange(COLUMNS):
        cap = 0#sentinal to find the column cap for the key
        for j in range(ROWS+1)[::-1]:
            if cap:
                if (key >> (i*(1+ROWS)+j))&1:
                    board1 += 1L << (i*(1+ROWS)+j)
                else:
                    board2 += 1L << (i*(1+ROWS)+j)
            else:
                if (key >> (i*(1+ROWS)+j))&1:
                    cap = 1
                    
        
        
    big = ''
    for i in xrange(ROWS):
        s = '|'
        for j in xrange(COLUMNS):
            s += ' '
            if (board1 >> (i + j * (1 + ROWS))) & 1:
                s += 'x'
            elif (board2 >> (i + j * (1 + ROWS))) & 1:
                s += 'o'
            else:
                s += ' '
            s += '|'
        big = s + '\n' + big
    print big
    return board1,board2
    
    
cpdef void smart_debug(Board board):
    cdef int128 moves[MAX_COLUMNS]
    cdef int num_moves
    num_moves = board.get_smart_moves(moves)
    if num_moves == -1:
        print 'win' , log(moves[0])/7
        return
    if num_moves == 0:
        print 'lose', log(moves[0])/7
        return
    print 'number of moves', num_moves
    print [log(moves[i])/7 for i in xrange(num_moves)]
    
cpdef void insert_debug():
    cdef int scores[7]
    cdef move moves[7]
    push_scores = [0,11,-8,3,2,1,-10]
    push_moves = [0,1,2,3,4,5,6]
    for i in xrange(7):
        insert(scores,moves,push_scores[i],push_moves[i],i)
    print scores
    print moves
    

def push_debug():
    init_twobig()
    global pushes
    print pushes
    push_twobig(3,1,7,4,2,<char>'e')
    print twobig[17].big.key != -1
    print twobig[17].big.key != <int64> -1
    
    print pushes
    
def pull_debug():    
    entry = pull_twobig(3)
    
    print entry.value
    print entry.depth
    
def get_twobig_entry(i):
#     print (twobig[i].big.key,twobig[i].big.value,twobig[i].big.depth,twobig[i].big.move,twobig[i].big.size,twobig[i].big.node)
#     print (twobig[i].small.key,twobig[i].small.value,twobig[i].small.depth,twobig[i].small.move,twobig[i].small.size,twobig[i].small.node)
    return twobig[i%PRIME]
    
    

cpdef bitindex_debug(int128 bitmove):    
    print bitindex(bitmove)