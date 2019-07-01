function  [pos_arr, X0] = Block_matching(im, par, noiseImage, Class, origin_pos, iter, initialSigma)
    searchRadius      = 21;
    patchSize         = par.patchSize;
    patchSize2        = patchSize^2;
    step              = par.step;
    %trashHold = 3 * par.sigma^2 * patchSize^2;

    N                 = size(im,1)-patchSize+1;
    M                 = size(im,2)-patchSize+1;
    rows              = [1:step:N];;
    rows              = [rows rows(end)+1:N];;
    columns           = [1:step:M];
    columns           = [columns columns(end)+1:M];
    L                 = N*M;
    X                 = zeros(patchSize*patchSize, L, 'single');

    k    =  0;
    for i  = 1:patchSize
        for j  = 1:patchSize
            k    =  k+1;
            blk  =  im(i:end-patchSize+i,j:end-patchSize+j);
            X(k,:) =  blk(:)';
        end
    end
    %Combine and changed by KazukiAmakawa
    X0 = X;
    if Class == 0    
        pos_arr = origin_pos;
    else
        if par.patch_method == 1
            I     =   (1:L);
            I     =   reshape(I, N, M);
            N1    =   length(rows);
            M1    =   length(columns);
            X         =  X';
            pos_arr   =  zeros(par.patchStackSize, N1*M1 );
            for  i  =  1 : N1
                row     =   rows(i);
                for  j  =  1 : M1
                    col     =   columns(j);
                    off     =  (col-1)*N + row;
                    off1    =  (j-1)*N1 + i;  
                            
                    rmin    =   max( row-searchRadius, 1 );
                    rmax    =   min( row+searchRadius, N );
                    cmin    =   max( col-searchRadius, 1 );
                    cmax    =   min( col+searchRadius, M );
                     
                    idx     =   I(rmin:rmax, cmin:cmax);
                    idx     =   idx(:);
                    patchesInSearchArea       =   X(idx, :);        
                    currentPatch       =   X(off, :);
                    
                    dis = 0;
                    for k = 1:patchSize2
                        dis   =  dis + (patchesInSearchArea(:,k) - currentPatch(k)).^2;
                    end
                    dis   =  dis./patchSize2;
                    [val,ind]   =  sort(dis);
                    %ind(val >= trashHold) = [];
                    pos_arr(:,off1)  =  idx( ind(1:par.patchStackSize) );   

                end
            end

        elseif (par.patch_method == 21) || (par.patch_method == 31) || (par.patch_method == 22) || (par.patch_method == 32) || (par.patch_method == 33)
            %Gaussian Mixture Model Method with BFS nearist researching
            %Added by KazkiAmakawa, source code from 
            [par1, model] = GMMInitial(initialSigma, im);
                                %Import parameter and GMM pre-trained model
            [X1, Sigma_arr] = GMMim2patch(im, noiseImage, par1);
                                %Import data and sigma distance
            [gmm_MY,gmm_ks,gmm_group,gmm_nSig,gmm_PF] = GMM(Sigma_arr, X1, par1, model);

            if (par.patch_method == 21) || (par.patch_method == 22)
                Cluster = gmm_ks;
                MaxSort = 250;
            elseif (par.patch_method == 31) || (par.patch_method == 32) || (par.patch_method == 33)
                if gmm_nSig<=15
                    par1.Maxgroupsize = round(par1.Maxgroupsize/2);
                end
                [KmeansCluster, FCSort] = FineCluster(noiseImage, gmm_group, gmm_ks, gmm_PF, par1, gmm_MY, iter, Sigma_arr);
                MaxSort = FCSort;
                Cluster = KmeansCluster;
            end

            if (par.patch_method == 21) || (par.patch_method == 31)
                bfstime   = clock;
                N1        = length(rows);
                M1        = length(columns); 
                locx      = [-1, -1, -1,  0, 0,  1, 1, 1];
                locy      = [-1,  0,  1, -1, 1, -1, 0, 1];
                Total_Val = 0;
                pos_arr   = zeros(par.patchStackSize, N1 * M1);
                
                %BFS for search first par.patchStackSize's values 
                for j = 1: M1
                    for i = 1:N1
                        row               = rows(i);
                        col               = columns(j);
                        Total_Val         = Total_Val + 1;
                        Block_id          = (col-1)*N + row; 
                        cluster_id        = Cluster(Block_id);
                        p                 = [];
                        q                 = [];
                        val               = 1;
                        p                 = [p, col];
                        q                 = [q, row];
                        stack_var         = 1;
                        saveimg           = zeros(M, N);
                        saveimg(col, row) = 1;

                        while 1
                            itemx         = p(val);
                            itemy         = q(val);
                            if Cluster((itemx-1)*N + itemy) == cluster_id
                                pos_arr(stack_var, Total_Val) = (itemx-1)*N + itemy;
                                stack_var = stack_var + 1;
                            end
                            if stack_var > par.patchStackSize
                                break;
                            end
                            val = val + 1;
                            
                            for kase = 1:8
                                currentx = itemx + locx(kase);
                                currenty = itemy + locy(kase);
                                if currentx < 1 || currentx > M || currenty < 1 || currenty > N
                                    continue;
                                end
                                if saveimg(currentx, currenty) == 0
                                    p = [p, currentx];
                                    q = [q, currenty];
                                    saveimg(currentx, currenty) = 1;
                                else
                                    continue;
                                end
                            end

                            if val > length(p)
                                break;
                            end
                        end 
                        
                        if stack_var <= par.patchStackSize
                            while 1
                                pos_arr(stack_var, Total_Val) = Block_id;
                                stack_var = stack_var + 1;
                                if stack_var > par.patchStackSize
                                    break;
                                end
                            end
                        end

                    end
                end
                %BFS for search first par.patchStackSize's values 

            elseif (par.patch_method == 22) || (par.patch_method == 32)
                sort_result      = zeros(MaxSort, par.patchSize * par.patchSize);
                total_sort       = zeros(1, MaxSort);
                not_zero_set     = 0;
                for kase = 1: length(Cluster)
                    clus_id      = Cluster(kase);
                    clus_vector  = X(1:end, kase);
                    total_sort(clus_id) = total_sort(clus_id) + 1;
                    for map_kase = 1: length(clus_vector)
                        sort_result(clus_id, map_kase) = sort_result(clus_id, map_kase) + clus_vector(map_kase);
                    end
                end
                for kase = 1: size(sort_result, 1)
                    if total_sort(kase) == 0
                        continue 
                    end
                    not_zero_set = not_zero_set + 1;
                    sort_result(kase, 1:end) = sort_result(kase, 1:end) / total_sort(kase);
                end
                
                Distance_Vector  = zeros(length(Cluster), 3);
                for kase = 1: length(Cluster)
                    clus_id      = Cluster(kase);
                    clus_vector  = X(1:end, kase);
                    cent_vector  = sort_result(clus_id, 1:end);
                    distance_val = norm(clus_vector - cent_vector);
                    Distance_Vector(kase, 1) = clus_id;
                    Distance_Vector(kase, 2) = distance_val;
                    Distance_Vector(kase, 3) = kase;
                end
                Distance_Vector  = sortrows(Distance_Vector, 1);
                start_cluster    = 1;
                end_cluster      = 0;
                current_cluster  = Distance_Vector(1, 1);
                current_tensor   = 0;
                pos_arr          = zeros(par.patchStackSize, not_zero_set);
                
                for kase = 1: length(Cluster)
                    if Distance_Vector(kase, 1) ~= current_cluster || kase + 1 > length(Cluster)
                        if kase ~= length(Cluster) 
                            end_cluster = kase - 1;
                        else
                            end_cluster = kase;
                        end
                        current_cluster = Distance_Vector(kase, 1);
                        current_tensor  = current_tensor + 1;
                        Sub_Vector      = Distance_Vector(start_cluster: end_cluster, 1: end);
                        start_cluster   = kase;

                        if size(Sub_Vector, 1) <= par.patchStackSize
                            for patch_loc = 1: length(Sub_Vector)
                                pos_arr(patch_loc, current_tensor) = Sub_Vector(patch_loc, 3);
                            end
                            for val = patch_loc + 1: par.patchStackSize
                                pos_arr(val, current_tensor)       = Sub_Vector(patch_loc, 3);
                            end
                        else
                            Sub_Vector                             = sortrows(Sub_Vector, 2);
                            for patch_loc = 1: par.patchStackSize
                                pos_arr(patch_loc, current_tensor) = Sub_Vector(patch_loc, 3);
                            end
                        end
                    end
                end

            elseif (par.patch_method == 33)
                total_sort       = zeros(1, MaxSort);
                true_sort        = zeros(1, MaxSort);
                not_zero_set     = 0;
                for kase = 1: length(Cluster)
                    clus_id      = Cluster(kase);
                    total_sort(clus_id) = total_sort(clus_id) + 1;
                end

                max_length       = max(total_sort);
                for kase = 1: MaxSort
                    if total_sort(kase) ~= 0
                        not_zero_set = not_zero_set + 1;
                        true_sort(kase) = not_zero_set;
                    end
                end
                not_zero_set
                max_length

                max_mark         = zeros(not_zero_set);
                pos_arr          = zeros(not_zero_set, max_length) + 1;
                for kase = 1: length(Cluster)
                    clus_id      = Cluster(kase);
                    true_id      = true_sort(clus_id);
                    max_mark(true_id) = max_mark(true_id) + 1;
                    true_val     = max_mark(true_id);
                    pos_arr(true_id, true_val) = kase;


            end
           
        end
    end
end

